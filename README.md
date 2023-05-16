# ✨ So you want to sponsor a contest

This `README.md` contains a set of checklists for our contest collaboration.

Your contest will use two repos: 
- **a _contest_ repo** (this one), which is used for scoping your contest and for providing information to contestants (wardens)
- **a _findings_ repo**, where issues are submitted (shared with you after the contest) 

Ultimately, when we launch the contest, this contest repo will be made public and will contain the smart contracts to be reviewed and all the information needed for contest participants. The findings repo will be made public after the contest report is published and your team has mitigated the identified issues.

Some of the checklists in this doc are for **C4 (🐺)** and some of them are for **you as the contest sponsor (⭐️)**.

---

## ⭐️ Sponsor: Edit this README

Under "SPONSORS ADD INFO HERE" heading below, include the following:

- [x] Modify the bottom of this `README.md` file to describe how your code is supposed to work with links to any relevent documentation and any other criteria/details that the C4 Wardens should keep in mind when reviewing. ([Here's a well-constructed example.](https://github.com/code-423n4/2022-08-foundation#readme))
  - [x] When linking, please provide all links as full absolute links versus relative links
  - [x] All information should be provided in markdown format (HTML does not render on Code4rena.com)
- [x] Under the "Scope" heading, provide the name of each contract and:
  - [x] source lines of code (excluding blank lines and comments) in each
  - [ ] external contracts called in each
  - [x] libraries used in each
- [x] Describe any novel or unique curve logic or mathematical models implemented in the contracts
- [x] Does the token conform to the ERC-20 standard? In what specific ways does it differ?
- [x] Describe anything else that adds any special logic that makes your approach unique
- [x] Identify any areas of specific concern in reviewing the code
- [x] Optional / nice to have: pre-record a high-level overview of your protocol (not just specific smart contract functions). This saves wardens a lot of time wading through documentation.
- [x] See also: [this checklist in Notion](https://code4rena.notion.site/Key-info-for-Code4rena-sponsors-f60764c4c4574bbf8e7a6dbd72cc49b4#0cafa01e6201462e9f78677a39e09746)
- [ ] Delete this checklist and all text above the line below when you're ready.

---

# Juicebox Buyback Delegate contest details
- Total Prize Pool: $24,500 USDC 
  - HM awards: 17,000 USDC
  - QA report awards: $1,000 USDC 
  - Gas report awards: $2,000 USDC 
  - Judge awards: $2,400 USDC
  - Lookout awards: $1,600 USDC 
  - Scout awards: $500 USDC
- Join [C4 Discord](https://discord.gg/code4rena) to register
- Submit findings [using the C4 form](https://code4rena.com/contests/2023-05-juicebox-buyback-delegate/submit)
- [Read our guidelines for more details](https://docs.code4rena.com/roles/wardens)
- Starts May 18, 2023 20:00 UTC
- Ends May 22, 2023 20:00 UTC

## Automated Findings / Publicly Known Issues

Automated findings output for the contest can be found [here](add link to report) within 24 hours of contest opening.

*Note for C4 wardens: Anything included in the automated findings output is considered a publicly known issue and is ineligible for awards.*

[ ⭐️ SPONSORS ADD INFO HERE ]

# Overview

`juice-buyback` provides a [data source](https://docs.juicebox.money/dev/learn/glossary/data-source/) and [delegate](https://docs.juicebox.money/dev/learn/glossary/delegate/) which maximise the [project token](https://docs.juicebox.money/dev/learn/glossary/tokens/) received by the contributor when they call `pay` on the [terminal](https://docs.juicebox.money/dev/learn/glossary/payment-terminal/). In order to do so, the delegate will either mint new tokens from the project ("vanilla" path, bypassing the delegate) or use the funds from `pay` to buy existing tokens in a Uniswap V3 pool ("buyback" path), depending on the best quote available at the time of the call.

This first iteration is optimised for ETH as terminal token.

To learn more about the Juicebox protocol, see our [docs](https://docs.juicebox.money/). To learn more about `juice-buyback`, see its [README](juice-buyback/README.md).

# Scope

| Contract | SLOC | Purpose | Libraries used |  
| ----------- | ----------- | ----------- | ----------- |
| [`juice-buyback/contracts/JBXBuybackDelegate.sol`](juice-buyback/contracts/JBXBuybackDelegate.sol) | 160 | The buyback delegate | [`@openzeppelin/*`](https://openzeppelin.com/contracts/) [`@jbx-protocol/juice-contracts-v3/*`](https://github.com/jbx-protocol/juice-contracts-v3) [`@paulrberg/contracts/math/PRBMath.sol`](https://github.com/PaulRBerg/prb-math) [`@uniswap/v3-core/*`](https://github.com/Uniswap/v3-core) [`@uniswap/v3-periphery/contracts/interfaces/external/IWETH9.sol`](https://github.com/Uniswap/v3-periphery/blob/main/contracts/interfaces/external/IWETH9.sol) |

## Out of scope

Other contracts.

# Additional Context

## Scoping Details 

```
- If you have a public code repo, please share it here: [`juice-buyback`](https://github.com/jbx-protocol/juice-buyback/)
- How many contracts are in scope?: 1
- Total SLoC for these contracts?:  160
- How many external imports are there?:  17
- How many separate interfaces and struct definitions are there for the contracts within scope?:  1
- Does most of your code generally use composition or inheritance?:   
- How many external calls?: 5
- What is the overall line coverage percentage provided by your tests?: 100
- Is there a need to understand a separate part of the codebase / get context in order to audit this part of the protocol?: yes
- Please describe required context: Juicebox [pay](https://docs.juicebox.money/dev/build/treasury-extensions/pay-delegate/) & [redeem](https://docs.juicebox.money/dev/build/treasury-extensions/redemption-delegate/) delegates
- Does it use an oracle?: no
- Does the token conform to the ERC20 standard?: yes
- Are there any novel or unique curve logic or mathematical models?: no
- Does it use a timelock function?: no
- Is it an NFT?: no
- Does it have an AMM?: yes
- Is it a fork of a popular project?: no
- Does it use rollups?: no
- Is it multi-chain?: no
- Does it use a side-chain?: no
```

## About Juicebox

The Juicebox protocol is a programmable treasury. Projects can use it to configure how its tokens should be minted when it receives funds, and under what conditions those funds can be distributed to preprogrammed addresses or reclaimed by its community. These rules can evolve over funding cycles, allowing people to bootstrap open-ended projects and add structure, constraints, extensions, and incentives over time as needed.

When people pay a project, they interact with a [payment terminal](https://docs.juicebox.money/dev/learn/glossary/payment-terminal/), a contract which controls the inflows and outflows of a certain token for every project which uses it. Projects can override the default payment terminal behavior through the use of data sources and delegates.

A [data source](https://docs.juicebox.money/dev/learn/glossary/data-source/) is used to provide custom data to a payment terminal's `pay` (or `redeem`) function. Data sources must adhere to [`IJBFundingCycleDataSource`](https://docs.juicebox.money/dev/api/interfaces/ijbfundingcycledatasource/).

A [pay delegate](https://docs.juicebox.money/dev/learn/glossary/delegate/) includes a custom `didPay(...)` hook that will execute after all of the default protocol pay logic has successfully executed in the terminal contract. Pay delegates must adhere to [`IJBPayDelegate`](https://docs.juicebox.money/dev/api/interfaces/ijbpaydelegate/).

`juice-buyback` is an `IJBPayDelegate` *and* an `IJBFundingCycleDataSource`.

# Tests

Anyone can deploy `juice-buyback` using the provided forge script.

To run this repo, you'll need [Foundry](https://book.getfoundry.sh/) and [NodeJS](https://nodejs.dev/en/learn/how-to-install-nodejs/) installed.

Install the dependencies with `npm install && git submodule update --init --force --recursive`, you should then be able to run the tests using `forge test` or deploy a new delegate using `forge script Deploy` (and the correct arguments, based on the chain and key you want to use - see the [Foundry docs](https://book.getfoundry.sh/)).
