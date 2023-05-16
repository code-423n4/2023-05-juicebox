# Juice Buyback Delegate - ETH-Project token

## Summary

Provides a datasource and delegate which maximise the project token received by the contributor when they call `pay` on the terminal. In order to do so, the delegate will either mint new tokens ("vanilla" path, bypassing the delegate) or swap existing token in an Uniswap V3 pool ("buyback" path), depending on the best quote available at the time of the call.

This first iteration is optimised for ETH as terminal token.

## Design
### Flow
- The frontend passes a quote (as an amount received for a given amount send) from the correct Uniswap V3 pool, as well as a maximum slippage allowed (in 1/10000th) while calling `pay(..)`. These should be encoded as uint256 and passed as third and fourth words of the `pay(..)` metadata parameter (the first 2 32bytes being reserved for the protocol).
- `Pay(..)` will use the buyback delegate as datasource and, based on the quote (taking slippage into account) and the funding cycle weight, will either mint (bypassing the delegate and using the regular terminal logic) or swap (signaling this by returning the delegate address and a 0 weight to the terminal).
- If swap is privilegied, the terminal will call the delegate's `didPay` method, which will wrap and swap the eth, and transfer the correct amount of project tokens to the contributor (ie the non-reserved ones).
NB: The whole amount contributed will be swapped, including what should be considered as reserved. The delegate will then burn/mint/burn again the non-transfered to account for the reserved tokens (ie burn them all, then mint an amount which will return the correct amount of reserved token, then burn the non-reserved token just minted)
- In case of failure of the swap (eg max slippage, low liquidity), the delegate will mint the tokens instead (using the original funding cycle weight and reserved rate).

### Contracts/Interfaces
- JBXBuyBackDelegate: the datasource, pay delegate and uniswap pool callback contract

## Usage
Anyone can deploy this delegate using the provided forge script.
To run this repo, you'll need [Foundry](https://book.getfoundry.sh/) and [NodeJS](https://nodejs.dev/en/learn/how-to-install-nodejs/) installed.
Install the dependencies with `npm install && git submodule update --init --force --recursive`, you should then be able to run the tests using `forge test` or deploy a new delegate using `forge script Deploy` (and the correct arguments, based on the chain and key you want to use - see the [Foundry docs](https://book.getfoundry.sh/)).

## Use-case
Maximizing the project token received by the contributor while leveling the funding cycle/secondary market price.

## Risk & trade-offs
 - This delegate is, for now, only compatible with ETH as terminal token.
 - This delegate relies on the liquidity available in an Uniswap V3. If LP migrate to a new pool or another DEX, this delegate would need to be redeployed.
 - A low liquidity might, if the max slippage isn't set properly, lead to an actual amount of token received lower than expected.