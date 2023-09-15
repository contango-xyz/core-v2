# Contango Protocol V2

Contango V2 is a new way of building perpetual contracts on top of existing money markets. When a trader opens a position, the protocol borrows on a money market, swaps on the spot market, then lends back on the same money market. Join us at [contango.xyz](https://contango.xyz). 


## Warning
This code is provided as-is, with no guarantees of any kind.

### Pre Requisites
Before running any command, make sure to install dependencies:

```
$ forge install
```

### Lint

```
$ forge fmt
```

### Test
Be sure to have an `.env` file located at root (or to have the following ENV variables)  
`MAINNET_URL=<your rpc url>`  
`ARBITRUM_URL=<your rpc url>`  
`OPTIMISM_URL=<your rpc url>`  
`POLYGON_URL=<your rpc url>`  

Compile and test the smart contracts with [Foundry](https://getfoundry.sh/):

```
$ forge test
```

### Supported scenarios
All supported scenarios when creating/modifying/closing a position are linked in [this sheet](https://docs.google.com/spreadsheets/d/1uLRNJOn3uy2PR5H2QJ-X8unBRVCu1Ra51ojMjylPH90/edit#gid=0) along with its corresponding [tests](./test/core/functional/AbstractPositionLifeCycle.ft.t.sol)

## Bug Bounty
Contango is not offering bounties for bugs disclosed whilst our audits are in place, but if you wish to report a bug, please do so at [security@contango.xyz](mailto:security@contango.xyz). Please include full details of the vulnerability and steps/code to reproduce. We ask that you permit us time to review and remediate any findings before public disclosure.

## License
Unless the opposite is explicitly stated on the file header, all files in this repository are released under the [BSL 1.1](https://github.com/contango-xyz/core-v2/blob/master/LICENSE.md) license. 
