// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "./interfaces/ILoanBookV2.sol";
import "./lib/Utils.sol";

contract LoanBookV21 is Initializable, OwnableUpgradeable, AccessControlUpgradeable, UUPSUpgradeable {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct LoanRequest {
        uint256 requestedAmount;
        uint256 repaidAmount;
    }

    struct Group {
        EnumerableSetUpgradeable.AddressSet members;
        address manager;
        bool isOpen;
        IERC20Upgradeable token;
        uint256 availableFunding;
        mapping(address => LoanRequest[]) loanRequests;
        mapping(address => uint256) loansToUser;
    }

    mapping(uint256 => Group) private groups;
    mapping(address => uint256) public userOnGroup;
    uint256 public groupIdCounter;
    mapping(address => bool) public blockedAddresses;
    mapping(address => bool) public registeredMembers;
    mapping(uint256 => mapping(uint256 => GroupLoanRequest)) public groupLoanRequests;
    mapping(uint256 => mapping(uint256 => GroupLoan)) public groupLoans;
    mapping(uint256 => uint256) public groupLoanRequestCounter;
    mapping(uint256 => uint256) public groupLoanPools;
    mapping(address => mapping(uint256 => Loan)) public loans;
    mapping(address => uint256) loansToUser;
    mapping(address => bool) public userLoanStatus;
    mapping(address => mapping(uint256 => LoanRequestV2)) loanRequests;
    bool paused;
    mapping(uint256 => bool) public noSignOffGroups;
    mapping(uint256 => bool) public hasActiveGroupLoanRequest;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant MEMBER_ROLE = keccak256("MEMBER_ROLE");
    bytes32 public constant GROUP_MANAGER_ROLE = keccak256("GROUP_MANAGER_ROLE");
    bytes32 public constant GROUP_MEMBER_ROLE = keccak256("GROUP_MEMBERS_ROLE");
    bytes32 public constant GROUP_SIGNATORY_ROLE = keccak256("GROUP_SIGNATORY_ROLE");
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private status;

    event GroupCreated(uint256 indexed groupId, address indexed manager, address tokenAddress, bool noSignOff);
    event GroupClosed(uint256 indexed groupId);
    event GroupOpened(uint256 indexed groupId);
    event MemberAdded(uint256 indexed groupId, address indexed member);
    event MemberRemoved(uint256 indexed groupId, address indexed member);
    event LoanRepaid(uint256 indexed groupId, address indexed borrower, uint256 loanId, uint256 amount);
    event ManagerChanged(uint256 indexed groupId, address indexed oldManager, address indexed newManager);
    event MemberRegistered(address indexed member);
    event MemberUnregistered(address indexed member);
    event GroupLoanRequested(
        uint256 indexed groupId, uint256 indexed requestId, uint256 requestedAmount, uint256 tenor, Status status
    );
    event GroupLoanApproved(uint256 indexed groupId, uint256 indexed requestId, uint256 requestedAmount);
    event GroupLoanRejected(uint256 indexed groupId, uint256 indexed requestId, uint256 requestedAmount);

    event LoanApplied(
        address indexed borrower,
        uint256 indexed groupId,
        uint256 requestId,
        uint256 requestedAmount,
        address token,
        uint256 tenor,
        Status status,
        Frequency frequency,
        uint256 installmentAmount,
        uint8 numberOfInstallments
    );

    event LoanApproved(
        address indexed member, uint256 indexed requestId, uint256 requestedAmount, uint256 tenor, uint256 groupId
    );
    event LoanRejected(
        address indexed member, uint256 indexed requestId, uint256 requestedAmount, uint256 tenor, uint256 groupId
    );
    event LoanPartiallyRepaid(uint256 indexed groupId, address indexed borrower, uint256 loanId, uint256 amount);
    event LoanStatusUpdated(address indexed member, uint256 indexed requestId, Status status, uint256 groupId);

    // Group Management

    function createGroup(address _manager, address _tokenAddress, bool noSignOffRequired)
        public
        screening
        onlyRole(MEMBER_ROLE)
        nonReentrant()
    {
        if (!hasRole(MEMBER_ROLE, _manager)) revert NotRegistered();
        uint256 groupId = groupIdCounter++;
        Group storage group = groups[groupId];
        group.isOpen = true;
        group.manager = _manager;
        group.members.add(_manager);
        group.token = IERC20Upgradeable(_tokenAddress);
        _grantRole(GROUP_MANAGER_ROLE, _manager);
        _grantRole(GROUP_SIGNATORY_ROLE, _manager);
        _grantRole(GROUP_MEMBER_ROLE, _manager);
        userOnGroup[_manager] = groupId; // To be confirmed later
        noSignOffRequired ? noSignOffGroups[groupId] = true : false;
        emit GroupCreated(groupId, _manager, _tokenAddress, noSignOffRequired);
    }

    function addMembers(address[] memory _members, uint256 _groupId) public screening onlyAdminOrAmanager {
        uint256 groupId;
        if (hasRole(ADMIN_ROLE, msg.sender)) {
            groupId = _groupId;
        } else {
            groupId = userOnGroup[msg.sender];
            assert(msg.sender == groups[groupId].manager);
        }

        _groupOpenCheck(groupId);

        for (uint256 i = 0; i < _members.length;) {
            if (!hasRole(MEMBER_ROLE, _members[i])) revert NotRegistered();
            if (userOnGroup[_members[i]] != 0) revert AlreadyInGroup();
            Group storage group = groups[groupId];
            group.members.add(_members[i]);
            _grantRole(GROUP_MEMBER_ROLE, _members[i]);
            userOnGroup[_members[i]] = groupId;
            emit MemberAdded(groupId, _members[i]);
            unchecked {
                i++;
            }
        }
    }

    function removeMembers(address[] memory _members) public screening onlyRole(GROUP_MANAGER_ROLE) {
        uint256 _groupId = userOnGroup[msg.sender];
        _groupOpenCheck(_groupId);
        assert(msg.sender == groups[_groupId].manager);
        for (uint256 i = 0; i < _members.length;) {
            if (userOnGroup[_members[i]] != _groupId) revert NotGroupMember();
            if (userLoanStatus[_members[i]]) revert ExistingLoan();
            Group storage group = groups[_groupId];
            group.members.remove(_members[i]);
            _revokeRole(GROUP_MEMBER_ROLE, _members[i]);
            if (hasRole(GROUP_SIGNATORY_ROLE, _members[i])) {
                _revokeRole(GROUP_SIGNATORY_ROLE, _members[i]);
            }
            userOnGroup[_members[i]] = 0;
            emit MemberRemoved(_groupId, _members[i]);
            unchecked {
                i++;
            }
        }
    }

    function leaveGroup() public screening {
        uint256 _groupId = userOnGroup[msg.sender];
        if (_groupId == 0) revert NotGroupMember();
        if (userLoanStatus[msg.sender]) revert ExistingLoan();
        Group storage group = groups[_groupId];
        group.members.remove(msg.sender);
        _revokeRole(GROUP_MEMBER_ROLE, msg.sender);
        if (hasRole(GROUP_SIGNATORY_ROLE, msg.sender)) {
            _revokeRole(GROUP_SIGNATORY_ROLE, msg.sender);
        }
        userOnGroup[msg.sender] = 0;
        emit MemberRemoved(_groupId, msg.sender);
    }

    function changeManager(uint256 _groupId, address _newManager) external onlyRole(ADMIN_ROLE) {
        if (!hasRole(MEMBER_ROLE, _newManager)) revert NotRegistered();
        if (!groups[_groupId].isOpen) revert Closed();
        if (!groups[_groupId].members.contains(_newManager)) {
            userOnGroup[_newManager] = _groupId;
            groups[_groupId].members.add(_newManager);
            _grantRole(GROUP_MEMBER_ROLE, _newManager);
            emit MemberAdded(_groupId, _newManager);
        }

        address oldManager = groups[_groupId].manager;
        groups[_groupId].manager = _newManager;
        _grantRole(GROUP_MANAGER_ROLE, _newManager);
        _grantRole(GROUP_SIGNATORY_ROLE, _newManager);
        _revokeRole(GROUP_MANAGER_ROLE, oldManager);
        emit ManagerChanged(_groupId, oldManager, _newManager);
    }

    function setGroupStatus(uint256 _groupId, bool _isOpen) external onlyRole(ADMIN_ROLE) {
        if (!groups[_groupId].isOpen && !_isOpen) revert NoChange();
        groups[_groupId].isOpen = _isOpen;
        if (_isOpen) {
            emit GroupOpened(_groupId);
        } else {
            emit GroupClosed(_groupId);
        }
    }

    // Admin Member/Misc Functions

    function sendERC20(address _tokenAddress, address _to, uint256 _amount) external onlyOwner {
        IERC20Upgradeable token = IERC20Upgradeable(_tokenAddress);
        token.safeTransfer(_to, _amount);
    }

    function registerMembers(address[] calldata _members) external onlyRole(ADMIN_ROLE) {
        uint256 totalCost = _members.length * 0.15 ether; // Calculate the total required CELO

        // Ensure the contract has enough CELO to cover the transfers
        require(address(this).balance >= totalCost, "Contract doesn't have enough CELO");

        for (uint256 i = 0; i < _members.length; i++) {
            registeredMembers[_members[i]] = true;
            grantRole(MEMBER_ROLE, _members[i]);

            // Send CELO to the new member
            (bool success,) = payable(_members[i]).call{value: 0.15 ether}("");
            require(success, "Failed to seed CELO");

            emit MemberRegistered(_members[i]);
        }
    }

    function unregisterMember(address _member) external onlyRole(ADMIN_ROLE) {
        registeredMembers[_member] = false;
        revokeRole(MEMBER_ROLE, _member);
        emit MemberUnregistered(_member);
    }

    function setBlockedAddress(address _address, bool _isBlocked) public onlyRole(ADMIN_ROLE) {
        if (owner() == _address) revert NotAdmin();
        blockedAddresses[_address] = _isBlocked;
    }

    // Group Loan Requests

    function requestGroupLoan(uint256 _groupId, uint256 _requestedAmount, uint256 _tenor)
        public
        screening
        onlyAdminOrAmanager
    {
        _groupOpenCheck(_groupId);
        require(!hasActiveGroupLoanRequest[_groupId], "Group already has an active loan");
        Group storage group = groups[_groupId];
        if (!group.isOpen) revert Closed();
        if (!hasRole(ADMIN_ROLE, msg.sender)) {
            if (userOnGroup[msg.sender] != _groupId) revert NotManager();
        }
        uint256 requestId = groupLoanRequestCounter[_groupId];
        GroupLoanRequest storage groupLoanRequest = groupLoanRequests[_groupId][requestId];
        groupLoanRequest.requestId = requestId;
        groupLoanRequest.requestedAmount = _requestedAmount;
        groupLoanRequest.tenor = _tenor;
        groupLoanRequestCounter[_groupId]++;

        hasActiveGroupLoanRequest[_groupId] = true;
        emit GroupLoanRequested(_groupId, requestId, _requestedAmount, _tenor, Status.Requested);
    }

    function approveGroupLoanRequest(uint256 _groupId, uint256 _groupLoanId, uint256 _interestAmount)
        public
        onlyRole(ADMIN_ROLE)
    {
        uint256 requestedAmount = groupLoanRequests[_groupId][_groupLoanId].requestedAmount;
        uint256 tenor = groupLoanRequests[_groupId][_groupLoanId].tenor;

        groupLoanPools[_groupId] += requestedAmount;

        GroupLoan storage groupLoan = groupLoans[_groupId][_groupLoanId];
        groupLoan.id = _groupLoanId;
        groupLoan.principalAmount = requestedAmount;
        groupLoan.interestAmount = _interestAmount;
        groupLoan.repaidPrincipalAmount = 0;
        groupLoan.repaidInterestAmount = 0;
        groupLoan.remainingPrincipal = requestedAmount;
        groupLoan.remainingInterest = _interestAmount;
        groupLoan.lastRepaymentDate = 0;
        groupLoan.disbursedDate = block.timestamp;
        groupLoan.maturityDate = block.timestamp + tenor;
        groupLoan.tenor = tenor;
        groupLoan.status = Status.Active;

        hasActiveGroupLoanRequest[_groupId] = false;
        emit GroupLoanApproved(_groupId, _groupLoanId, requestedAmount);

        if (noSignOffGroups[_groupId]) {
            address manager = groups[_groupId].manager;
            this.requestLoan(
                requestedAmount,
                _interestAmount,
                tenor,
                Frequency.Monthly,
                1,
                address(groups[_groupId].token),
                _groupId,
                manager
            );
        }
    }

    function rejectGroupLoanRequest(uint256 _groupId, uint256 _groupLoanId) public onlyRole(ADMIN_ROLE) {
        GroupLoanRequest storage groupLoanRequest = groupLoanRequests[_groupId][_groupLoanId];
        groupLoanRequest.status = Status.Rejected;

        hasActiveGroupLoanRequest[_groupId] = false;

        emit GroupLoanRejected(_groupId, _groupLoanId, groupLoanRequest.requestedAmount);
    }

    function signOffLoanRequest(address _member, uint256 _requestId) public screening onlyRole(GROUP_SIGNATORY_ROLE) {
        if (!hasRole(MEMBER_ROLE, _member)) revert NotRegistered();
        LoanRequestV2 storage loanRequest = loanRequests[_member][_requestId];
        if (loanRequest.status != Status.Requested) revert NotRequested();
        if (userOnGroup[msg.sender] != loanRequest.groupId) {
            revert NotSignatory();
        }
        if (loanRequest.signatories.length == 2) revert LoanSignedOff();
        if (_addressExists(loanRequest.signatories, msg.sender)) {
            revert Signed();
        }
        loanRequest.signatories.push(msg.sender);

        if (loanRequest.signatories.length == 2) {
            loanRequest.status = Status.Signed;
            emit LoanStatusUpdated(_member, _requestId, Status.Signed, userOnGroup[_member]);
        }
    }

    // Loan Requests/Repayment

    function requestLoan(
        uint256 _requestedAmount,
        uint256 _interestAmount,
        uint256 _tenor,
        Frequency _frequency,
        uint8 _numberOfInstallments,
        address _token,
        uint256 _groupId,
        address _borrower
    ) public screening {
        address borrower;
        if (_borrower != address(0)) {
            if (!hasRole(ADMIN_ROLE, msg.sender)) revert NotAdmin();
            borrower = _borrower;
        } else {
            borrower = msg.sender;
        }

        if (_groupId != 0) {
            if (!hasRole(GROUP_MEMBER_ROLE, borrower)) revert NotGroupMember();
        } else {
            if (!hasRole(MEMBER_ROLE, borrower)) revert NotRegistered();
        }

        performLoanValidityChecks();

        if (_numberOfInstallments < 1) revert InvalidNumberOfInstallments();
        uint256 userLoanId = loansToUser[borrower]++;

        LoanRequestV2 storage loanRequest = loanRequests[borrower][userLoanId];

        loanRequest.groupId = _groupId != 0 ? userOnGroup[borrower] : 0;
        loanRequest.borrower = borrower;
        loanRequest.requestId = userLoanId;
        loanRequest.requestedAmount = _requestedAmount;
        loanRequest.interestAmount = _interestAmount;
        loanRequest.tenor = _tenor;
        loanRequest.status = Status.Requested;
        loanRequest.frequency = _frequency;
        loanRequest.numberOfInstallments = _numberOfInstallments;
        loanRequest.installmentAmount = (_requestedAmount + _interestAmount) / _numberOfInstallments;
        loanRequest.token = _token;

        userLoanStatus[borrower] = true;

        emit LoanApplied(
            borrower,
            _groupId != 0 ? userOnGroup[borrower] : 0, // groupId is 0 for individual loans
            userLoanId,
            _requestedAmount,
            _token,
            _tenor,
            loanRequest.status,
            _frequency,
            loanRequest.installmentAmount,
            _numberOfInstallments
        );

        // Check if no sign-off is required for this group
        if (_groupId != 0 && noSignOffGroups[_groupId]) {
            loanRequest.status = Status.Signed;
            emit LoanStatusUpdated(borrower, userLoanId, Status.Signed, userOnGroup[borrower]);
        }
    }

    function approveLoan(address _member, uint256 _requestId, uint256 _groupId) public screening nonReentrant {
        if (_groupId != 0) {
            _groupOpenCheck(_groupId);
            if (!hasRole(GROUP_MANAGER_ROLE, msg.sender)) revert NotManager();
        } else {
            if (!hasRole(ADMIN_ROLE, msg.sender)) revert NotAdmin();
        }

        LoanRequestV2 storage loanRequest = loanRequests[_member][_requestId];

        if (_groupId != 0) {
            if (loanRequest.status != Status.Signed) revert NotSigned();
            if (groups[loanRequest.groupId].manager != msg.sender) {
                revert NotManager();
            }
        } else {
            if (loanRequest.status != Status.Requested) revert NotRequested();
        }

        checkFunds(loanRequest);

        if (_groupId != 0) {
            groupLoanPools[loanRequest.groupId] -= loanRequest.requestedAmount;
        }

        IERC20(loanRequest.token).transfer(_member, loanRequest.requestedAmount);

        Loan storage loan = loans[_member][_requestId];
        loan.borrower = _member;
        loan.id = _requestId;
        loan.groupId = loanRequest.groupId;
        loan.principalAmount = loanRequest.requestedAmount;
        loan.interestAmount = loanRequest.interestAmount;
        loan.repaidAmount = 0;
        loan.lastRepaymentDate = 0;
        loan.disbursedDate = block.timestamp;
        loan.maturityDate = block.timestamp + loanRequest.tenor;
        loan.tenor = loanRequest.tenor;
        loan.status = Status.Active;
        loan.frequency = loanRequest.frequency;
        loan.token = loanRequest.token;
        loan.numberOfInstallments = loanRequest.numberOfInstallments;
        loan.installmentAmount = loanRequest.installmentAmount;
        loan.dueDate = loan.disbursedDate + loanRequest.tenor * 1 days;

        emit LoanApproved(_member, _requestId, loanRequest.requestedAmount, loanRequest.tenor, loanRequest.groupId);
    }

    function rejectLoan(address _member, uint256 _requestId, uint256 _groupId) public screening {
        if (_groupId != 0) {
            if (!hasRole(GROUP_MANAGER_ROLE, msg.sender)) revert NotManager();
        } else {
            if (!hasRole(ADMIN_ROLE, msg.sender)) revert NotAdmin();
        }

        LoanRequestV2 storage loanRequest = loanRequests[_member][_requestId];
        loanRequest.status = Status.Rejected;
        userLoanStatus[_member] = false;
        emit LoanRejected(_member, _requestId, loanRequest.requestedAmount, loanRequest.tenor, loanRequest.groupId);
    }

    function repayLoanV2(uint256 _requestId, uint256 _amount, uint256 _groupId, address borrower)
        public
        screening
        nonReentrant
    {
        if (_groupId != 0) {
            if (!hasRole(GROUP_MEMBER_ROLE, borrower)) revert NotGroupMember();
        } else {
            if (!hasRole(MEMBER_ROLE, borrower)) revert NotRegistered();
        }

        Loan storage loan = loans[borrower][_requestId];
        if (loan.status != Status.Active) revert NotActive();

        IERC20(loan.token).transferFrom(msg.sender, address(this), _amount);

        loan.repaidAmount += _amount;
        loan.lastRepaymentDate = block.timestamp;

        if (loan.repaidAmount < (loan.principalAmount + loan.interestAmount)) {
            emit LoanPartiallyRepaid(loan.groupId, borrower, _requestId, _amount);
        }

        if (loan.repaidAmount >= (loan.principalAmount + loan.interestAmount)) {
            if (loan.dueDate + 30 days >= loan.lastRepaymentDate) {
                emit LoanRepaid(loan.groupId, loan.borrower, loan.id, loan.repaidAmount);
                loan.status = Status.Repaid;
            } else {
                loan.status = Status.PaidLate;
                emit LoanStatusUpdated(borrower, _requestId, Status.PaidLate, loan.groupId);
            }
            userLoanStatus[borrower] = false;
        }
    }

    function repayLoan(uint256 _groupId, uint256 _loanId, uint256 _amount) external  {
        require(groups[_groupId].isOpen, "Group is closed");
        require(groups[_groupId].members.contains(msg.sender), "Not a group member");
        require(_loanId < groups[_groupId].loanRequests[msg.sender].length, "Invalid loan ID");
        groups[_groupId].token.safeTransferFrom(msg.sender, address(this), _amount);
        groups[_groupId].loanRequests[msg.sender][_loanId].repaidAmount += _amount;
        groups[_groupId].availableFunding += _amount;
        emit LoanRepaid(_groupId, msg.sender, _loanId, _amount);
    }

    // Helper functions

    function getGroupLoanRequest(uint256 _groupId, uint256 groupLoanId)
        public
        view
        returns (GroupLoanRequest memory groupLoan)
    {
        return groupLoanRequests[_groupId][groupLoanId];
    }

    function getGroup(uint256 _groupId) external view returns (address, uint256, IERC20Upgradeable, bool, uint256) {
        Group storage group = groups[_groupId];
        return (group.manager, group.availableFunding, group.token, group.isOpen, group.members.length());
    }

    function getGroupLoan(uint256 _groupId, uint256 _groupLoanId) public view returns (GroupLoan memory groupLoan) {
        return groupLoans[_groupId][_groupLoanId];
    }

    function getLoan(address _member, uint256 _groupLoanId) public view returns (Loan memory loan) {
        return loans[_member][_groupLoanId];
    }

    function getLoanRequest(address _member, uint256 _requestId)
        public
        view
        returns (LoanRequestV2 memory loanRequest)
    {
        return loanRequests[_member][_requestId];
    }

    function performLoanValidityChecks() internal view {
        if (userLoanStatus[msg.sender]) revert ExistingLoan();
    }

    function _addressExists(address[] memory addresses, address _address) internal pure returns (bool) {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (addresses[i] == _address) {
                return true;
            }
        }
        return false;
    }

    function _groupOpenCheck(uint256 _groupId) internal view {
        if (!groups[_groupId].isOpen) revert Closed();
    }

    function checkFunds(LoanRequestV2 memory loanRequest) internal view {
        // Confirm the Smart contract has enough funds
        uint256 tokenBalance = IERC20(loanRequest.token).balanceOf(address(this));

        if (loanRequest.requestedAmount > tokenBalance) {
            revert InsufficientContractFunds();
        }

        // If group loan, confirm the group has enough funds
        if (loanRequest.groupId != 0 && loanRequest.requestedAmount > groupLoanPools[loanRequest.groupId]) {
            revert InsufficientGroupFunds();
        }
    }

    function topUpGroupLoanPool(uint256 _groupId, uint256 _amount) public screening onlyRole(ADMIN_ROLE) {
        if (!groups[_groupId].isOpen) revert Closed();
        groupLoanPools[_groupId] += _amount;
    }

    // modifiers

    modifier screening() {
        if (blockedAddresses[msg.sender]) revert Blocked();
        if (paused) revert ContractPaused();
        _;
    }

    modifier nonReentrant() {
        if (status == _ENTERED) revert Reentrant();
        status = _ENTERED;
        _;
        status = _NOT_ENTERED;
    }

    modifier onlyAdminOrAmanager() {
        if (!hasRole(GROUP_MANAGER_ROLE, msg.sender) && !hasRole(ADMIN_ROLE, msg.sender)) revert NotManager();
        _;
    }

    /*
    _________________________________________________________________________________________________

    UUPS UPGRADE, AND ROLE HELPERS
    _________________________________________________________________________________________________
    */

    // Override _authorizeUpgrade function required by UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    // Grant roles helper
    function grantAdminRole(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(ADMIN_ROLE, account);
    }

    function grantUpgraderRole(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(UPGRADER_ROLE, account);
    }

    function grantSignatoryRole(address _member) public screening onlyAdminOrAmanager {
        if (!hasRole(MEMBER_ROLE, _member)) revert NotRegistered();

        if (!hasRole(ADMIN_ROLE, msg.sender)) {
            if (userOnGroup[_member] != userOnGroup[msg.sender]) {
                revert NotGroupMember();
            }
        }
        _grantRole(GROUP_SIGNATORY_ROLE, _member);
    }

    // Revoke roles helper
    function revokeAdminRole(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(ADMIN_ROLE, account);
    }

    function revokeUpgraderRole(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(UPGRADER_ROLE, account);
    }

    // Override transferOwnership to also manage roles
    function transferOwnership(address newOwner) public override onlyOwner {
        address oldOwner = owner();

        // Transfer ownership
        super.transferOwnership(newOwner);

        // Grant roles to the new owner
        _setupRole(DEFAULT_ADMIN_ROLE, newOwner);
        _setupRole(UPGRADER_ROLE, newOwner);

        // Revoke roles from the old owner
        _revokeRole(DEFAULT_ADMIN_ROLE, oldOwner);
        _revokeRole(UPGRADER_ROLE, oldOwner);
    }

    // Pause contract
    function togglePause(bool _status) public onlyRole(ADMIN_ROLE) {
        if (paused == _status) revert NoChange();
        paused = !paused;
    }

    function updateLoanStatus(address _member, uint256 _requestId, Status _status) public onlyRole(ADMIN_ROLE) {
        loans[_member][_requestId].status = _status;
    }

    function emptyGroupPool(uint256 _groupId) public onlyRole(ADMIN_ROLE) {
        groupLoanPools[_groupId] = 0;
    }
}
