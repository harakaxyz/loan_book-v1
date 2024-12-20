# LoanBook Smart Contract

## Overview

The `LoanBook` smart contract is designed to manage group-based lending on the Celo blockchain. It allows for the creation of lending groups, management of members, and handling of loan requests and repayments within each group. Built on Solidity `0.8.20`, the contract leverages OpenZeppelin's upgradeable contracts framework to ensure future improvements can be made without disrupting the existing ecosystem or data.

## Features

- **Group Management**: Create and manage lending groups with distinct managers and members.
- **Role-Based Access Control**: Utilize OpenZeppelin's Access Control to assign roles and permissions.
- **Loan Handling**: Manage loan requests and repayments.
- **Funding Groups**: Allow funding to groups which can then be lent out to members.
- **Upgradeable**: Built using OpenZeppelin's UUPS upgradeable pattern, allowing for new features and fixes to be added post-deployment.
