# LoanBook Smart Contract

## Overview

LoanBook is a decentralized application deployed on the Celo blockchain designed to facilitate group lending activities. It enables users to manage lending groups efficiently through features like creating groups, adding and managing members, funding, and handling loans. 

## Features

### Contract Components

#### Structs
- **LoanRequest**: Structure to manage the amount requested by a member and the amount that has been repaid.
- **Group**: Structure representing a lending group including details like members, a manager, and financial transactions like loans and funding.

#### Events
- **GroupCreated**: Emitted when a new lending group is created.
- **GroupClosed**: Emitted when a group is closed.
- **MemberAdded, MemberRemoved**: Emitted when members are added to or removed from a group.
- **MembersAdded, MembersRemoved**: Emitted when multiple members are added or removed.
- **GroupFunded**: Emitted when any amount of funds is added to a group's balance.
- **LoanRequested**: Emitted when a loan is requested by a group member.
- **LoanRepaid**: Emitted when a loan is repaid by a group member.
- **ManagerChanged**: Emitted when the manager of a group is changed.

#### Modifiers
- **onlyOwnerOrManager**: Ensures that only the owner or the manager of the group can execute certain functions.
- **onlyGroupMember**: Ensures that only members of a specific group can execute certain functions.

### Functionalities

#### Group Management
- **createGroup**: Create a new lending group.
- **closeGroup**: Close an existing group.
- **addMember, removeMember**: Manage individual group members.
- **addMembers, removeMembers**: Manage multiple group members at once.
- **changeManager**: Change the manager of the group.

#### Funding Operations
- **fundGroup**: Add funds to a group's balance to be available for lending.

#### Loan Management
- **requestLoan**: Members can request loans from the group's fund.
- **repayLoan**: Members can repay loans to the group's fund.

#### ERC20 Token Operations
- **sendERC20**: Allows the contract owner to send ERC20 tokens from the contract to a specified wallet address.

#### Information Retrieval
- **getGroup**: Retrieve details about a specific group.

## Installation

To deploy the LoanBook contract, you need:
- A Celo wallet setup
- Enough CELO to cover gas fees
- Node.js installed
- Truffle or Hardhat for compiling and deploying smart contracts
