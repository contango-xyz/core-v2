//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SignedMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import "../libraries/Roles.sol";
import "../libraries/Errors.sol";
import "../libraries/MathLib.sol";
import "../libraries/Validations.sol";
import "../interfaces/IOrderManager.sol";
import "../interfaces/IContango.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IContangoOracle.sol";

uint256 constant TOLERANCE_UNIT = 1e4;

uint128 constant INITIAL_GAS_START = 21_000;
uint256 constant GAS_PER_BYTE = 16;
uint256 constant ERC20_TRANSFERS_GAS_ESTIMATE = 30_000;
uint256 constant TWO_ERC20_TRANSFERS_GAS_ESTIMATE = ERC20_TRANSFERS_GAS_ESTIMATE * 2;

uint256 constant MAX_GAS_MULTIPLIER = 10e4; // 10x
uint256 constant MIN_GAS_MULTIPLIER = 1e4; // 1x

contract OrderManager is IOrderManager, AccessControlUpgradeable, UUPSUpgradeable {

    using { toOrderId } for OrderParams;
    using { toTradeParams } for OrderStorage;
    using Math for *;
    using MathLib for *;
    using SignedMath for *;
    using SafeCast for *;
    using { validateCreatePositionPermissions, validateModifyPositionPermissions } for PositionNFT;

    struct OrderStorage {
        PositionId positionId;
        int128 quantity;
        uint128 limitPrice; // in quote currency
        uint128 tolerance; // in 1e4, e.g. 0.001e4 -> 0.1%
        int128 cashflow;
        Currency cashflowCcy;
        uint32 deadline;
        OrderType orderType;
        address owner;
    }

    IContango public immutable contango;
    PositionNFT public immutable positionNFT;
    IWETH9 public immutable nativeToken;
    IVault public immutable vault;
    IUnderlyingPositionFactory public immutable positionFactory;
    address public immutable treasury;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * mixins without shifting down storage in this contract.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     *
     * After adding some OZ mixins, we consumed 251 slots from the original 50k gap.
     */
    uint256[50_000 - 251] private __gap;

    uint128 public gasStart;
    uint64 public gasMultiplier; // multiplier in 1e4, e.g. 2.5e4 -> 25000 -> 2.5x
    uint64 public gasTip;
    IContangoOracle public oracle;

    mapping(OrderId id => OrderStorage order) private _orders;

    constructor(IContango _contango, address _treasury) {
        contango = _contango;
        positionNFT = _contango.positionNFT();
        vault = _contango.vault();
        positionFactory = _contango.positionFactory();
        nativeToken = _contango.vault().nativeToken();
        treasury = _treasury;
    }

    function initialize(Timelock timelock, uint64 _gasMultiplier, uint64 _gasTip, IContangoOracle _oracle) public initializer {
        __AccessControl_init_unchained();
        __UUPSUpgradeable_init_unchained();
        _grantRole(DEFAULT_ADMIN_ROLE, Timelock.unwrap(timelock));
        _setGasMultiplier(_gasMultiplier);
        gasStart = INITIAL_GAS_START;
        gasTip = _gasTip;
        oracle = _oracle;
    }

    // ====================================== Accessors ======================================

    function setGasMultiplier(uint64 _gasMultiplier) public override onlyRole(OPERATOR_ROLE) {
        _setGasMultiplier(_gasMultiplier);
    }

    function _setGasMultiplier(uint64 _gasMultiplier) private {
        if (_gasMultiplier > MAX_GAS_MULTIPLIER) revert AboveMaxGasMultiplier(_gasMultiplier);
        if (_gasMultiplier < MIN_GAS_MULTIPLIER) revert BelowMinGasMultiplier(_gasMultiplier);

        gasMultiplier = _gasMultiplier;
        emit GasMultiplierSet(_gasMultiplier);
    }

    function setGasTip(uint64 _gasTip) external override onlyRole(OPERATOR_ROLE) {
        gasTip = _gasTip;
        emit GasTipSet(_gasTip);
    }

    function setOracle(IContangoOracle _oracle) external override onlyRole(OPERATOR_ROLE) {
        oracle = _oracle;
        emit OracleSet(_oracle);
    }

    function orders(OrderId orderId) external view returns (Order memory order) {
        OrderStorage memory orderStorage = _orders[orderId];
        return Order({
            owner: orderStorage.owner,
            positionId: orderStorage.positionId,
            quantity: orderStorage.quantity,
            limitPrice: orderStorage.limitPrice,
            tolerance: orderStorage.tolerance,
            cashflow: orderStorage.cashflow,
            cashflowCcy: orderStorage.cashflowCcy,
            deadline: orderStorage.deadline,
            orderType: orderStorage.orderType
        });
    }

    function hasOrder(OrderId orderId) public view returns (bool) {
        return _orders[orderId].owner != address(0);
    }

    // ====================================== Orders ======================================

    function placeOnBehalfOf(OrderParams calldata params, address onBehalfOf) external returns (OrderId orderId) {
        return _place(params, onBehalfOf);
    }

    function place(OrderParams calldata params) external returns (OrderId orderId) {
        return _place(params, msg.sender);
    }

    function _place(OrderParams calldata params, address owner) internal returns (OrderId orderId) {
        orderId = _validatePlaceOrder(params, owner);
        _orders[orderId] = OrderStorage({
            owner: owner,
            positionId: params.positionId,
            quantity: params.quantity.toInt128(),
            limitPrice: params.limitPrice.toUint128(),
            tolerance: params.tolerance.toUint128(),
            cashflow: params.cashflow.toInt128(),
            cashflowCcy: params.cashflowCcy,
            deadline: params.deadline.toUint32(),
            orderType: params.orderType
        });

        emit OrderPlaced({
            orderId: orderId,
            positionId: params.positionId,
            owner: owner,
            quantity: params.quantity,
            limitPrice: params.limitPrice,
            tolerance: params.tolerance,
            cashflow: params.cashflow,
            cashflowCcy: params.cashflowCcy,
            deadline: params.deadline,
            orderType: params.orderType,
            placedBy: msg.sender
        });
    }

    function cancel(OrderId orderId) external orderExists(orderId) {
        // allow for expired orders cleanup
        OrderStorage memory order = _orders[orderId];
        bool notExpired = block.timestamp <= order.deadline;
        if (notExpired && !positionNFT.isApprovedForAll(order.owner, msg.sender)) revert Unauthorised(msg.sender);

        delete _orders[orderId];
        emit OrderCancelled(orderId);
    }

    function execute(OrderId orderId, ExecutionParams calldata execParams)
        external
        payable
        returns (PositionId positionId, Trade memory trade_, uint256 keeperReward)
    {
        FeeParams memory feeParams;
        return executeWithFees(orderId, execParams, feeParams);
    }

    function executeWithFees(OrderId orderId, ExecutionParams calldata execParams, FeeParams memory feeParams)
        public
        payable
        gasMeasured
        onlyRole(BOT_ROLE)
        orderExists(orderId)
        returns (PositionId positionId, Trade memory trade_, uint256 keeperReward)
    {
        OrderStorage memory order = _orders[orderId];
        if (block.timestamp > order.deadline) revert OrderExpired(orderId, order.deadline, block.timestamp);

        (Symbol symbol,,, uint256 number) = order.positionId.decode();
        if (number > 0 && order.owner != positionNFT.positionOwner(order.positionId)) revert OrderInvalidated(orderId);

        (positionId, trade_) = order.quantity > 0 ? _open(order, execParams) : _close(order, execParams);
        delete _orders[orderId];

        if (feeParams.amount > 0) {
            _withdraw(feeParams.token, order.owner, feeParams.amount, treasury);
            emit FeeCollected(orderId, positionId, order.owner, treasury, feeParams.token, feeParams.amount, feeParams.basisPoints);
        }

        IERC20 cashflowToken;
        {
            Instrument memory instrument = contango.instrument(symbol);
            // If cashflowCcy is None, we use the quote for keeper rewards
            cashflowToken = order.cashflowCcy == Currency.Base ? instrument.base : instrument.quote;

            keeperReward = _keeperReward(order.positionId, cashflowToken);
            emit OrderExecuted(orderId, positionId, keeperReward);
        }

        if (keeperReward > 0) _withdraw(cashflowToken, order.owner, keeperReward, msg.sender);

        if (trade_.cashflow < 0) {
            _withdraw(cashflowToken, order.owner, trade_.cashflow.abs() - keeperReward - feeParams.amount, order.owner);
        }
    }

    function _withdraw(IERC20 cashflowToken, address account, uint256 amount, address to) internal returns (uint256) {
        return cashflowToken == nativeToken ? vault.withdrawNative(account, amount, to) : vault.withdraw(cashflowToken, account, amount, to);
    }

    function _open(OrderStorage memory order, ExecutionParams calldata execParams)
        internal
        returns (PositionId positionId, Trade memory trade_)
    {
        (positionId, trade_) = contango.tradeOnBehalfOf(order.toTradeParams(), execParams, order.owner);
    }

    function _close(OrderStorage memory order, ExecutionParams calldata execParams)
        internal
        returns (PositionId positionId, Trade memory trade_)
    {
        uint256 limitPrice = order.limitPrice;
        if (order.orderType == OrderType.StopLoss) {
            order.limitPrice = uint128(order.limitPrice.mulDiv(TOLERANCE_UNIT - order.tolerance, TOLERANCE_UNIT));
        }

        (positionId, trade_) = contango.trade(order.toTradeParams(), execParams);

        if (order.orderType == OrderType.StopLoss && trade_.forwardPrice > limitPrice) revert InvalidPrice(trade_.forwardPrice, limitPrice);
    }

    function _validatePlaceOrder(OrderParams calldata params, address owner) private returns (OrderId orderId) {
        orderId = params.toOrderId();

        // permission
        (Symbol symbol, MoneyMarketId mm,, uint256 number) = params.positionId.decode();
        Instrument memory instrument = contango.instrument(symbol);
        if (number > 0) {
            positionNFT.validateModifyPositionPermissions(params.positionId);

            IMoneyMarket moneyMarket = positionFactory.moneyMarket(params.positionId);
            bool fullyClosing = params.quantity.absIfNegative() >= moneyMarket.collateralBalance(params.positionId, instrument.base);
            if (fullyClosing && params.cashflowCcy == Currency.None) revert CashflowCcyRequired();
        } else {
            positionNFT.validateCreatePositionPermissions(owner);
            if (address(instrument.base) == address(0)) revert InvalidInstrument(symbol);
            // PositionFactory will blow on an invalid MM
            positionFactory.moneyMarket(mm);
        }

        // order params validation
        if (hasOrder(orderId)) revert OrderAlreadyExists(orderId);
        if (block.timestamp > params.deadline) revert InvalidDeadline(params.deadline, block.timestamp);
        if (params.quantity == 0) revert InvalidQuantity();
        if (params.quantity > 0 && params.orderType != OrderType.Limit) revert InvalidOrderType(params.orderType);
        if (params.quantity < 0) {
            if (params.orderType == OrderType.Limit) revert InvalidOrderType(params.orderType);
            if (params.orderType == OrderType.StopLoss && params.tolerance > TOLERANCE_UNIT) revert InvalidTolerance(params.tolerance);
        }
    }

    modifier orderExists(OrderId orderId) {
        if (!hasOrder(orderId)) revert OrderDoesNotExist(orderId);
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) { }

    // ====================================== Keeper ======================================

    modifier gasMeasured() {
        gasStart += gasleft().toUint128();
        _;
        gasStart = INITIAL_GAS_START;
    }

    function _keeperReward(PositionId positionId, IERC20 cashflowToken) internal view returns (uint256 keeperReward) {
        uint256 rate;
        uint256 unit;
        if (cashflowToken != nativeToken) {
            rate = oracle.priceInNativeToken(positionId, cashflowToken);
            unit = 10 ** cashflowToken.decimals();
        }

        // Keeper receives a multiplier of the gas cost
        keeperReward = _gasCost() * gasMultiplier / PERCENTAGE_UNIT;

        keeperReward = rate > 0 ? keeperReward.mulDiv(unit, rate) : keeperReward;
    }

    // Gas cost for L1 EVMs, this should be overridden for L2 EVMs
    function _gasCost() internal view virtual returns (uint256 gasCost) {
        // 21000 min tx gas (starting gasStart value) + gas used so far + 16 gas per byte of data + 60k for the 2 ERC20 transfers
        uint256 gasSpent = gasStart - gasleft() + GAS_PER_BYTE * msg.data.length + TWO_ERC20_TRANSFERS_GAS_ESTIMATE;

        uint256 baseFee = block.basefee;
        uint256 txTip = tx.gasprice - baseFee;

        // gas spent @ (current baseFee + capped tip)
        gasCost = gasSpent * (baseFee + Math.min(gasTip, txTip));
    }

}

function toOrderId(OrderParams memory params) pure returns (OrderId) {
    return OrderId.wrap(keccak256(abi.encode(params)));
}

function toTradeParams(OrderManager.OrderStorage memory params) pure returns (TradeParams memory tradeParams) {
    return TradeParams({
        positionId: params.positionId,
        quantity: params.quantity,
        cashflow: params.cashflow,
        cashflowCcy: params.cashflowCcy,
        limitPrice: params.limitPrice
    });
}
