// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts@4.9.6/access/Ownable.sol";
import "@openzeppelin/contracts@4.9.6/access/AccessControl.sol";
import "@openzeppelin/contracts@4.9.6/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts@4.9.6/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts@4.9.6/token/ERC20/utils/SafeERC20.sol";

contract LoanBook is Ownable, AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    struct LoanRequest {
        uint256 requestedAmount;
        uint256 repaidAmount;
    }

    struct Group {
        EnumerableSet.AddressSet members;
        address manager;
        bool isOpen;
        IERC20 token;
        uint256 availableFunding;
        mapping(address => LoanRequest[]) loanRequests;
        mapping(address => uint256) loansToUser;
    }

    mapping(uint256 => Group) private groups;
    uint256 public groupIdCounter;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    event GroupCreated(uint256 indexed groupId, address indexed manager, address tokenAddress);
    event GroupClosed(uint256 indexed groupId);
    event MemberAdded(uint256 indexed groupId, address indexed member);
    event MemberRemoved(uint256 indexed groupId, address indexed member);
    event MembersAdded(uint256 indexed groupId, address[] members);
    event MembersRemoved(uint256 indexed groupId, address[] members);
    event GroupFunded(uint256 indexed groupId, address indexed funder, uint256 amount);
    event LoanRequested(uint256 indexed groupId, address indexed borrower, uint256 loanId, uint256 amount);
    event LoanRepaid(uint256 indexed groupId, address indexed borrower, uint256 loanId, uint256 amount);
    event ManagerChanged(uint256 indexed groupId, address indexed oldManager, address indexed newManager);

    constructor()  {
        _grantRole(keccak256("ADMIN_ROLE"), msg.sender);
        _setRoleAdmin(MANAGER_ROLE, keccak256("ADMIN_ROLE"));
    }

    function createGroup(address _manager, address _tokenAddress) external onlyOwner {
        uint256 groupId = groupIdCounter++;
        groups[groupId].isOpen = true;
        groups[groupId].manager = _manager;
        groups[groupId].members.add(_manager);
        groups[groupId].token = IERC20(_tokenAddress);
        grantRole(MANAGER_ROLE, _manager);
        emit GroupCreated(groupId, _manager, _tokenAddress);
    }

    function closeGroup(uint256 _groupId) external onlyOwner {
        require(groups[_groupId].isOpen, "Group is already closed");
        groups[_groupId].isOpen = false;
        emit GroupClosed(_groupId);
    }

    function addMember(uint256 _groupId, address _member) external onlyOwnerOrManager(_groupId) {
        require(groups[_groupId].isOpen, "Group is closed");
        groups[_groupId].members.add(_member);
        emit MemberAdded(_groupId, _member);
    }

    function removeMember(uint256 _groupId, address _member) external onlyOwnerOrManager(_groupId) {
        require(groups[_groupId].isOpen, "Group is closed");
        groups[_groupId].members.remove(_member);
        emit MemberRemoved(_groupId, _member);
    }

    function addMembers(uint256 _groupId, address[] memory _members) external onlyOwnerOrManager(_groupId) {
        require(groups[_groupId].isOpen, "Group is closed");
        for (uint256 i = 0; i < _members.length; i++) {
            groups[_groupId].members.add(_members[i]);
        }
        emit MembersAdded(_groupId, _members);
    }

    function removeMembers(uint256 _groupId, address[] memory _members) external onlyOwnerOrManager(_groupId) {
        require(groups[_groupId].isOpen, "Group is closed");
        for (uint256 i = 0; i < _members.length; i++) {
            groups[_groupId].members.remove(_members[i]);
        }
        emit MembersRemoved(_groupId, _members);
    }

    function fundGroup(uint256 _groupId, uint256 _amount) external {
        require(groups[_groupId].isOpen, "Group is closed");
        groups[_groupId].token.safeTransferFrom(msg.sender, address(this), _amount);
        groups[_groupId].availableFunding += _amount;
        emit GroupFunded(_groupId, msg.sender, _amount);
    }

    function requestLoan(uint256 _groupId, uint256 _amount) external onlyGroupMember(_groupId) {
        require(groups[_groupId].isOpen, "Group is closed");
        require(_amount <= groups[_groupId].availableFunding, "Requested amount exceeds available funding");
        uint256 loanId = groups[_groupId].loanRequests[msg.sender].length;
        groups[_groupId].token.safeTransfer(msg.sender, _amount);
        groups[_groupId].loanRequests[msg.sender].push(LoanRequest(_amount, 0));
        groups[_groupId].loansToUser[msg.sender] += 1;
        groups[_groupId].availableFunding -= _amount;
        emit LoanRequested(_groupId, msg.sender, loanId, _amount);
    }

    function repayLoan(uint256 _groupId, uint256 _loanId, uint256 _amount) external {
        require(groups[_groupId].isOpen, "Group is closed");
        require(groups[_groupId].members.contains(msg.sender), "Not a group member");
        require(_loanId < groups[_groupId].loanRequests[msg.sender].length, "Invalid loan ID");
        groups[_groupId].token.safeTransferFrom(msg.sender, address(this), _amount);
        groups[_groupId].loanRequests[msg.sender][_loanId].repaidAmount += _amount;
        groups[_groupId].availableFunding += _amount;
        emit LoanRepaid(_groupId, msg.sender, _loanId, _amount);
    }

    function changeManager(uint256 _groupId, address _newManager) external onlyOwner {
        require(groups[_groupId].isOpen, "Group is closed");
        address oldManager = groups[_groupId].manager;
        groups[_groupId].manager = _newManager;
        emit ManagerChanged(_groupId, oldManager, _newManager);
    }

    function sendERC20(address _tokenAddress, address _to, uint256 _amount) external onlyOwner {
        IERC20 token = IERC20(_tokenAddress);
        token.safeTransfer(_to, _amount);
    }

    function getGroup(uint256 _groupId) external view returns(address, uint256) {
        return (groups[_groupId].manager, groups[_groupId].availableFunding);
    }

    modifier onlyOwnerOrManager(uint256 _groupId) {
        require(owner() == msg.sender || groups[_groupId].manager == msg.sender, "Not authorized");
        _;
    }

    modifier onlyGroupMember(uint256 _groupId) {
        require(groups[_groupId].members.contains(msg.sender), "Not a group member");
        _;
    }
}