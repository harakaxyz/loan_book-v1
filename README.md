# LoanBook Smart Contract

## Overview

The `LoanBook` smart contract is designed to manage group-based lending on the Celo blockchain. It allows for the creation of lending groups, management of members, and handling of loan requests and repayments within each group. Built on Solidity `0.8.20`, the contract leverages OpenZeppelin's upgradeable contracts framework to ensure future improvements can be made without disrupting the existing ecosystem or data.

## Features

- **Group Management**: Create and manage lending groups with distinct managers and members.
- **Role-Based Access Control**: Utilize OpenZeppelin's Access Control to assign roles and permissions.
- **Loan Handling**: Manage loan requests and repayments.
- **Funding Groups**: Allow funding to groups which can then be lent out to members.
- **Upgradeable**: Built using OpenZeppelin's UUPS upgradeable pattern, allowing for new features and fixes to be added post-deployment.

## Functions

### Group Operations

- **createGroup(address _manager, address _tokenAddress)**
  - Create a new lending group with a designated manager and associated ERC20 token for transactions.
  - Only callable by the contract owner.

- **closeGroup(uint256 _groupId)**
  - Close an existing group, preventing any new loans or memberships.
  - Only callable by the contract owner.

### Member Management

- **addMember(uint256 _groupId, address _member)**
  - Add a new member to a specific group.
  - Only callable by the group manager or the contract owner.

- **removeMember(uint256 _groupId, address _member)**
  - Remove an existing member from a group.
  - Only callable by the group manager or the contract owner.

### Loan Management

- **requestLoan(uint256 _groupId, uint256 _amount)**
  - Request a loan from the group fund by a group member.
  - Conditions apply based on group funding and member status.

- **repayLoan(uint256 _groupId, uint256 _loanId, uint256 _amount)**
  - Repay a loan to the group's fund.
  - Ensures the caller is a group member and the loan ID is valid.

### Funding and Transactions

- **fundGroup(uint256 _groupId, uint256 _amount)**
  - Fund a group's available lending pool with the specified amount of ERC20 tokens.
  - Callable by any user who wishes to fund the group.

- **sendERC20(address _tokenAddress, address _to, uint256 _amount)**
  - Allows the contract owner to send ERC20 tokens from the contract to a specified address.

## Modifiers

- **onlyOwnerOrManager(uint256 _groupId)**
  - Ensures that either the contract owner or the group manager can execute a function.

- **onlyGroupMember(uint256 _groupId)**
  - Ensures that a function can only be called by a member of the specified group.

## Setup and Deployment

1. **Deployment**: The contract should be deployed using a proxy to ensure upgradeability.
2. **Initialization**: After deployment, the `initialize()` function must be called to set up the contract owner and prepare the contract for use.
