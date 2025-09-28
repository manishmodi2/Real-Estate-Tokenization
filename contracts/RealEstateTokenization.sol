// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title Real Estate Tokenization Contract
 * @dev A contract for tokenizing real estate properties as NFTs with fractional ownership capabilities
 * @notice This contract allows property owners to tokenize real estate and sell fractional shares
 */
contract RealEstateTokenization is ERC721, ERC721URIStorage, Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    using Address for address payable;
    using SafeMath for uint256;
    
    Counters.Counter private _tokenIdCounter;
    
    struct Property {
        uint256 tokenId;
        string propertyAddress;
        string description;
        uint256 totalValue;
        uint256 totalShares;
        uint256 availableShares;
        uint256 pricePerShare;
        address propertyOwner;
        bool isActive;
        bool isPaused;
        uint256 creationTime;
        uint256 lastRentPerShare;
        uint256 totalRentDistributed;
        uint256 lastValueUpdate;
        string propertyType; // "Residential", "Commercial", "Industrial", "Land"
        uint256 squareFootage;
        uint256 totalInvestment;
    }
    
    struct SharePurchase {
        uint256 propertyId;
        address buyer;
        uint256 shares;
        uint256 totalCost;
        uint256 timestamp;
        uint256 pricePerShare;
    }

    struct RentDistribution {
        uint256 propertyId;
        uint256 totalRent;
        uint256 timestamp;
        uint256 rentPerShare;
        uint256 distributionIndex;
    }

    struct Shareholder {
        address shareholder;
        uint256 shares;
        uint256 investment;
        uint256 lastClaimIndex;
        uint256 joinTimestamp;
    }
    
    // Voting system for major decisions
    struct Vote {
        uint256 propertyId;
        string proposal;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 endTime;
        bool executed;
        address creator;
        mapping(address => bool) hasVoted;
        mapping(address => uint256) votesCast;
    }
    
    // Constants
    uint256 public constant MAX_FEE = 1000; // 10% maximum
    uint256 public constant VOTING_DURATION = 7 days;
    uint256 public constant QUORUM_PERCENTAGE = 51; // 51% required
    uint256 public constant MIN_SHARES = 1;
    uint256 public constant MAX_BULK_PURCHASES = 10;
    
    // State variables
    mapping(uint256 => Property) public properties;
    mapping(uint256 => SharePurchase[]) public propertyPurchases;
    mapping(address => uint256[]) public userProperties;
    mapping(uint256 => RentDistribution[]) public rentDistributions;
    mapping(uint256 => Shareholder[]) public propertyShareholders;
    
    // Efficient mappings
    mapping(uint256 => mapping(address => uint256)) public propertyShareholdings;
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) public rentClaims;
    mapping(uint256 => mapping(address => uint256)) public userInvestment;
    mapping(uint256 => mapping(address => uint256)) public lastRentClaimIndex;
    mapping(address => uint256) public totalUserInvestment;
    
    // Fee structure
    uint256 public platformFeePercentage = 250; // 2.5% (basis points)
    address public feeRecipient;
    
    // Voting
    Vote[] public votes;
    mapping(uint256 => uint256[]) public propertyVotes;
    
    // Emergency stop
    bool public emergencyStop = false;
    
    // Events
    event PropertyTokenized(
        uint256 indexed tokenId,
        string propertyAddress,
        uint256 totalValue,
        uint256 totalShares,
        address indexed owner
    );
    
    event SharesPurchased(
        uint256 indexed propertyId,
        address indexed buyer,
        uint256 shares,
        uint256 totalCost,
        uint256 platformFee
    );
    
    event SharesTransferred(
        uint256 indexed propertyId,
        address indexed from,
        address indexed to,
        uint256 shares
    );

    event PropertyPaused(uint256 indexed propertyId, bool isPaused);
    
    event PropertyValueUpdated(
        uint256 indexed propertyId, 
        uint256 oldValue, 
        uint256 newValue
    );
    
    event RentDistributed(
        uint256 indexed propertyId,
        uint256 totalRent,
        uint256 timestamp
    );
    
    event RentClaimed(
        uint256 indexed propertyId,
        address indexed shareholder,
        uint256 amount
    );

    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);
    
    event PropertyDeactivated(uint256 indexed propertyId);

    event VoteCreated(uint256 indexed voteId, uint256 propertyId, string proposal);
    event VoteCast(uint256 indexed voteId, address voter, bool support, uint256 shares);
    event VoteExecuted(uint256 indexed voteId, bool passed);
    
    event PropertyMetadataUpdated(uint256 indexed propertyId, string description, string propertyType);
    event EmergencyStop(bool stopped);
    event FundsRecovered(address token, uint256 amount);
    event PropertyOwnerUpdated(uint256 indexed propertyId, address newOwner);

    // Modifiers
    modifier onlyPropertyOwner(uint256 propertyId) {
        require(properties[propertyId].propertyOwner == msg.sender, "RET: Not property owner");
        _;
    }
    
    modifier propertyActive(uint256 propertyId) {
        require(properties[propertyId].isActive, "RET: Property not active");
        _;
    }
    
    modifier propertyNotPaused(uint256 propertyId) {
        require(!properties[propertyId].isPaused, "RET: Property trading paused");
        _;
    }

    modifier validProperty(uint256 propertyId) {
        require(properties[propertyId].tokenId == propertyId, "RET: Invalid property ID");
        _;
    }

    modifier onlyShareholder(uint256 propertyId) {
        require(propertyShareholdings[propertyId][msg.sender] > 0, "RET: Not a shareholder");
        _;
    }

    modifier notInEmergency() {
        require(!emergencyStop, "RET: Contract in emergency stop");
        _;
    }
    
    modifier validShares(uint256 shares) {
        require(shares >= MIN_SHARES, "RET: Shares below minimum");
        _;
    }

    constructor() ERC721("RealEstateTokens", "RET") Ownable(msg.sender) {
        feeRecipient = msg.sender;
    }
    
    /**
     * @dev Tokenize a real estate property as an NFT with fractional ownership
     * @param propertyAddress Physical address of the property
     * @param description Property description
     * @param totalValue Total property value in wei
     * @param totalShares Number of shares to issue
     * @param propertyType Type of property
     * @param squareFootage Area in square feet
     * @param metadataURI IPFS URI for property metadata
     */
    function tokenizeProperty(
        string memory propertyAddress,
        string memory description,
        uint256 totalValue,
        uint256 totalShares,
        string memory propertyType,
        uint256 squareFootage,
        string memory metadataURI
    ) public nonReentrant notInEmergency returns (uint256) {
        require(bytes(propertyAddress).length > 0, "RET: Property address cannot be empty");
        require(totalValue > 0, "RET: Total value must be greater than 0");
        require(totalShares > 0, "RET: Total shares must be greater than 0");
        require(totalValue >= totalShares, "RET: Value must be at least equal to shares");
        require(bytes(metadataURI).length > 0, "RET: Metadata URI cannot be empty");
        
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        
        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, metadataURI);
        
        Property storage newProperty = properties[tokenId];
        newProperty.tokenId = tokenId;
        newProperty.propertyAddress = propertyAddress;
        newProperty.description = description;
        newProperty.totalValue = totalValue;
        newProperty.totalShares = totalShares;
        newProperty.availableShares = totalShares;
        newProperty.pricePerShare = totalValue / totalShares;
        newProperty.propertyOwner = msg.sender;
        newProperty.isActive = true;
        newProperty.isPaused = false;
        newProperty.creationTime = block.timestamp;
        newProperty.lastRentPerShare = 0;
        newProperty.totalRentDistributed = 0;
        newProperty.lastValueUpdate = block.timestamp;
        newProperty.propertyType = propertyType;
        newProperty.squareFootage = squareFootage;
        newProperty.totalInvestment = 0;
        
        userProperties[msg.sender].push(tokenId);
        
        emit PropertyTokenized(tokenId, propertyAddress, totalValue, totalShares, msg.sender);
        
        return tokenId;
    }
    
    /**
     * @dev Purchase shares of a tokenized property
     * @param propertyId ID of the property
     * @param shares Number of shares to purchase
     */
    function purchaseShares(
        uint256 propertyId, 
        uint256 shares
    ) public payable nonReentrant notInEmergency
      validProperty(propertyId)
      propertyActive(propertyId)
      propertyNotPaused(propertyId)
      validShares(shares)
    {
        Property storage property = properties[propertyId];
        
        require(shares <= property.availableShares, "RET: Not enough shares available");
        
        uint256 totalCost = shares * property.pricePerShare;
        require(msg.value >= totalCost, "RET: Insufficient payment");
        
        // Calculate platform fee
        uint256 platformFee = (totalCost * platformFeePercentage) / 10000;
        uint256 ownerPayment = totalCost - platformFee;
        
        // Update property state
        property.availableShares -= shares;
        property.totalInvestment += totalCost;
        
        // Update user state
        propertyShareholdings[propertyId][msg.sender] += shares;
        userInvestment[propertyId][msg.sender] += totalCost;
        totalUserInvestment[msg.sender] += totalCost;
        
        // Record the purchase
        propertyPurchases[propertyId].push(SharePurchase({
            propertyId: propertyId,
            buyer: msg.sender,
            shares: shares,
            totalCost: totalCost,
            timestamp: block.timestamp,
            pricePerShare: property.pricePerShare
        }));

        // Update shareholders list
        _updateShareholder(propertyId, msg.sender, shares, totalCost, true);
        
        // Add to user's property list if first time purchasing
        if (!_hasUserProperty(msg.sender, propertyId)) {
            userProperties[msg.sender].push(propertyId);
        }
        
        // Transfer payments using call for better security
        _safeTransfer(property.propertyOwner, ownerPayment);
        _safeTransfer(feeRecipient, platformFee);
        
        // Refund excess payment
        if (msg.value > totalCost) {
            _safeTransfer(msg.sender, msg.value - totalCost);
        }
        
        emit SharesPurchased(propertyId, msg.sender, shares, totalCost, platformFee);
    }

    /**
     * @dev Bulk purchase shares for multiple properties
     * @param propertyIds Array of property IDs
     * @param shares Array of share amounts for each property
     */
    function bulkPurchaseShares(
        uint256[] memory propertyIds,
        uint256[] memory shares
    ) public payable nonReentrant notInEmergency {
        require(propertyIds.length == shares.length, "RET: Arrays length mismatch");
        require(propertyIds.length > 0 && propertyIds.length <= MAX_BULK_PURCHASES, "RET: Invalid array length");
        
        uint256 totalCost = 0;
        
        // Calculate total cost first
        for (uint256 i = 0; i < propertyIds.length; i++) {
            Property storage property = properties[propertyIds[i]];
            require(property.isActive && !property.isPaused, "RET: Property not available");
            require(shares[i] >= MIN_SHARES, "RET: Shares below minimum");
            require(shares[i] <= property.availableShares, "RET: Not enough shares available");
            totalCost += shares[i] * property.pricePerShare;
        }
        
        require(msg.value >= totalCost, "RET: Insufficient payment");
        
        // Execute purchases
        for (uint256 i = 0; i < propertyIds.length; i++) {
            if (shares[i] > 0) {
                _purchaseSharesInternal(propertyIds[i], shares[i], msg.sender);
            }
        }
        
        // Refund excess payment
        if (msg.value > totalCost) {
            _safeTransfer(msg.sender, msg.value - totalCost);
        }
    }

    /**
     * @dev Internal function for share purchase
     */
    function _purchaseSharesInternal(uint256 propertyId, uint256 shares, address buyer) internal {
        Property storage property = properties[propertyId];
        uint256 totalCost = shares * property.pricePerShare;
        
        // Calculate platform fee
        uint256 platformFee = (totalCost * platformFeePercentage) / 10000;
        uint256 ownerPayment = totalCost - platformFee;
        
        // Update state
        property.availableShares -= shares;
        property.totalInvestment += totalCost;
        propertyShareholdings[propertyId][buyer] += shares;
        userInvestment[propertyId][buyer] += totalCost;
        totalUserInvestment[buyer] += totalCost;
        
        // Record purchase
        propertyPurchases[propertyId].push(SharePurchase({
            propertyId: propertyId,
            buyer: buyer,
            shares: shares,
            totalCost: totalCost,
            timestamp: block.timestamp,
            pricePerShare: property.pricePerShare
        }));

        _updateShareholder(propertyId, buyer, shares, totalCost, true);
        
        // Transfer payments
        _safeTransfer(property.propertyOwner, ownerPayment);
        _safeTransfer(feeRecipient, platformFee);
        
        emit SharesPurchased(propertyId, buyer, shares, totalCost, platformFee);
    }
    
    /**
     * @dev Transfer shares between users
     * @param propertyId ID of the property
     * @param to Recipient address
     * @param shares Number of shares to transfer
     */
    function transferShares(
        uint256 propertyId, 
        address to, 
        uint256 shares
    ) public nonReentrant notInEmergency
      validProperty(propertyId)
      propertyActive(propertyId)
      propertyNotPaused(propertyId)
      validShares(shares)
    {
        require(to != address(0), "RET: Cannot transfer to zero address");
        require(to != msg.sender, "RET: Cannot transfer to yourself");
        require(propertyShareholdings[propertyId][msg.sender] >= shares, "RET: Insufficient shares");
        
        // Calculate proportional investment
        uint256 totalInvestment = userInvestment[propertyId][msg.sender];
        uint256 investmentTransferred = (totalInvestment * shares) / propertyShareholdings[propertyId][msg.sender];
        
        // Update shareholdings
        propertyShareholdings[propertyId][msg.sender] -= shares;
        propertyShareholdings[propertyId][to] += shares;
        
        // Update investments
        userInvestment[propertyId][msg.sender] -= investmentTransferred;
        userInvestment[propertyId][to] += investmentTransferred;
        totalUserInvestment[msg.sender] -= investmentTransferred;
        totalUserInvestment[to] += investmentTransferred;

        // Update shareholders
        _updateShareholder(propertyId, msg.sender, shares, investmentTransferred, false);
        _updateShareholder(propertyId, to, shares, investmentTransferred, true);
        
        // Add to recipient's property list if first time
        if (!_hasUserProperty(to, propertyId)) {
            userProperties[to].push(propertyId);
        }
        
        emit SharesTransferred(propertyId, msg.sender, to, shares);
    }

    /**
     * @dev Create a vote for property-related decisions
     * @param propertyId ID of the property
     * @param proposal Description of the proposal
     */
    function createVote(
        uint256 propertyId,
        string memory proposal
    ) public validProperty(propertyId) onlyShareholder(propertyId) returns (uint256) {
        require(bytes(proposal).length > 0, "RET: Proposal cannot be empty");
        
        uint256 voteId = votes.length;
        
        Vote storage newVote = votes.push();
        newVote.propertyId = propertyId;
        newVote.proposal = proposal;
        newVote.endTime = block.timestamp + VOTING_DURATION;
        newVote.executed = false;
        newVote.creator = msg.sender;
        
        propertyVotes[propertyId].push(voteId);
        
        emit VoteCreated(voteId, propertyId, proposal);
        return voteId;
    }

    /**
     * @dev Cast a vote
     * @param voteId ID of the vote
     * @param support True for support, false against
     */
    function castVote(uint256 voteId, bool support) public notInEmergency {
        require(voteId < votes.length, "RET: Invalid vote ID");
        Vote storage vote = votes[voteId];
        require(block.timestamp <= vote.endTime, "RET: Voting ended");
        require(!vote.executed, "RET: Vote already executed");
        require(!vote.hasVoted[msg.sender], "RET: Already voted");
        
        uint256 voterShares = propertyShareholdings[vote.propertyId][msg.sender];
        require(voterShares > 0, "RET: Not a shareholder");
        
        vote.hasVoted[msg.sender] = true;
        vote.votesCast[msg.sender] = voterShares;
        
        if (support) {
            vote.votesFor += voterShares;
        } else {
            vote.votesAgainst += voterShares;
        }
        
        emit VoteCast(voteId, msg.sender, support, voterShares);
    }

    /**
     * @dev Execute a vote if conditions are met
     * @param voteId ID of the vote to execute
     */
    function executeVote(uint256 voteId) public notInEmergency {
        require(voteId < votes.length, "RET: Invalid vote ID");
        Vote storage vote = votes[voteId];
        require(block.timestamp > vote.endTime, "RET: Voting still active");
        require(!vote.executed, "RET: Vote already executed");
        require(msg.sender == vote.creator || msg.sender == owner(), "RET: Only creator or owner can execute");
        
        vote.executed = true;
        
        uint256 totalVotes = vote.votesFor + vote.votesAgainst;
        uint256 totalShares = properties[vote.propertyId].totalShares - properties[vote.propertyId].availableShares;
        
        bool passed = (totalVotes * 100 >= totalShares * QUORUM_PERCENTAGE) && 
                     (vote.votesFor > vote.votesAgainst);
        
        // Execute proposal logic based on the proposal content
        _executeProposal(vote.propertyId, vote.proposal, passed);
        
        emit VoteExecuted(voteId, passed);
    }

    /**
     * @dev Internal function to execute proposal actions
     */
    function _executeProposal(uint256 propertyId, string memory proposal, bool passed) internal {
        if (!passed) return;
        
        // Example proposal execution - in practice, you'd parse the proposal
        // and execute specific actions based on its content
        if (keccak256(abi.encodePacked(proposal)) == keccak256(abi.encodePacked("PAUSE_PROPERTY"))) {
            properties[propertyId].isPaused = true;
            emit PropertyPaused(propertyId, true);
        } else if (keccak256(abi.encodePacked(proposal)) == keccak256(abi.encodePacked("UNPAUSE_PROPERTY"))) {
            properties[propertyId].isPaused = false;
            emit PropertyPaused(propertyId, false);
        }
        // Add more proposal types as needed
    }

    /**
     * @dev Update shareholder information
     */
    function _updateShareholder(
        uint256 propertyId,
        address shareholder,
        uint256 shares,
        uint256 investment,
        bool isAdding
    ) internal {
        bool found = false;
        
        for (uint256 i = 0; i < propertyShareholders[propertyId].length; i++) {
            if (propertyShareholders[propertyId][i].shareholder == shareholder) {
                if (isAdding) {
                    propertyShareholders[propertyId][i].shares += shares;
                    propertyShareholders[propertyId][i].investment += investment;
                } else {
                    propertyShareholders[propertyId][i].shares = propertyShareholders[propertyId][i].shares - shares;
                    propertyShareholders[propertyId][i].investment = propertyShareholders[propertyId][i].investment - investment;
                    
                    if (propertyShareholders[propertyId][i].shares == 0) {
                        // Remove shareholder if no shares left
                        propertyShareholders[propertyId][i] = propertyShareholders[propertyId][propertyShareholders[propertyId].length - 1];
                        propertyShareholders[propertyId].pop();
                    }
                }
                found = true;
                break;
            }
        }
        
        if (!found && isAdding) {
            propertyShareholders[propertyId].push(Shareholder({
                shareholder: shareholder,
                shares: shares,
                investment: investment,
                lastClaimIndex: rentDistributions[propertyId].length,
                joinTimestamp: block.timestamp
            }));
        }
    }

    /**
     * @dev Safe transfer function to prevent reentrancy
     */
    function _safeTransfer(address to, uint256 amount) internal {
        if (amount > 0) {
            (bool success, ) = payable(to).call{value: amount}("");
            require(success, "RET: Transfer failed");
        }
    }

    // ============ ADMIN FUNCTIONS ============

    /**
     * @dev Update platform fee percentage
     * @param newFee New fee percentage in basis points (e.g., 250 = 2.5%)
     */
    function updatePlatformFee(uint256 newFee) public onlyOwner {
        require(newFee <= MAX_FEE, "RET: Fee too high");
        uint256 oldFee = platformFeePercentage;
        platformFeePercentage = newFee;
        emit PlatformFeeUpdated(oldFee, newFee);
    }

    /**
     * @dev Update fee recipient address
     * @param newRecipient New fee recipient address
     */
    function updateFeeRecipient(address newRecipient) public onlyOwner {
        require(newRecipient != address(0), "RET: Invalid recipient");
        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }

    /**
     * @dev Emergency stop mechanism
     * @param stop True to stop, false to resume
     */
    function setEmergencyStop(bool stop) public onlyOwner {
        emergencyStop = stop;
        emit EmergencyStop(stop);
    }

    /**
     * @dev Recover accidentally sent tokens
     * @param tokenAddress Address of token to recover (address(0) for ETH)
     * @param amount Amount to recover
     */
    function recoverTokens(address tokenAddress, uint256 amount) public onlyOwner {
        require(tokenAddress != address(0), "RET: Use withdrawETH for ETH");
        // Implementation for ERC20 token recovery would go here
        emit FundsRecovered(tokenAddress, amount);
    }

    /**
     * @dev Withdraw accidentally sent ETH
     * @param amount Amount of ETH to withdraw
     */
    function withdrawETH(uint256 amount) public onlyOwner {
        require(amount <= address(this).balance, "RET: Insufficient balance");
        _safeTransfer(owner(), amount);
        emit FundsRecovered(address(0), amount);
    }

    // ============ PROPERTY MANAGEMENT FUNCTIONS ============

    function pauseProperty(uint256 propertyId, bool isPaused) public 
        validProperty(propertyId) onlyPropertyOwner(propertyId) propertyActive(propertyId) {
        properties[propertyId].isPaused = isPaused;
        emit PropertyPaused(propertyId, isPaused);
    }

    function updatePropertyValue(uint256 propertyId, uint256 newValue) public 
        validProperty(propertyId) onlyPropertyOwner(propertyId) propertyActive(propertyId) {
        require(newValue > 0, "RET: New value must be greater than 0");
        
        Property storage property = properties[propertyId];
        uint256 oldValue = property.totalValue;
        property.totalValue = newValue;
        property.pricePerShare = newValue / property.totalShares;
        property.lastValueUpdate = block.timestamp;
        
        emit PropertyValueUpdated(propertyId, oldValue, newValue);
    }

    function distributeRent(uint256 propertyId) public payable 
        validProperty(propertyId) onlyPropertyOwner(propertyId) propertyActive(propertyId) {
        require(msg.value > 0, "RET: Rent amount must be greater than 0");
        
        Property storage property = properties[propertyId];
        uint256 soldShares = property.totalShares - property.availableShares;
        require(soldShares > 0, "RET: No shares sold yet");
        
        RentDistribution memory newDistribution = RentDistribution({
            propertyId: propertyId,
            totalRent: msg.value,
            timestamp: block.timestamp,
            rentPerShare: msg.value / soldShares,
            distributionIndex: rentDistributions[propertyId].length
        });
        
        rentDistributions[propertyId].push(newDistribution);
        property.totalRentDistributed += msg.value;
        property.lastRentPerShare = msg.value / soldShares;
        
        emit RentDistributed(propertyId, msg.value, block.timestamp);
    }

    function claimRent(uint256 propertyId, uint256 distributionIndex) public nonReentrant 
        validProperty(propertyId) propertyActive(propertyId) {
        require(distributionIndex < rentDistributions[propertyId].length, "RET: Invalid distribution index");
        require(propertyShareholdings[propertyId][msg.sender] > 0, "RET: No shares owned");
        require(!rentClaims[propertyId][distributionIndex][msg.sender], "RET: Rent already claimed");
        
        Property storage property = properties[propertyId];
        RentDistribution storage distribution = rentDistributions[propertyId][distributionIndex];
        
        uint256 userShares = propertyShareholdings[propertyId][msg.sender];
        uint256 soldShares = property.totalShares - property.availableShares;
        uint256 rentAmount = (distribution.totalRent * userShares) / soldShares;
        
        require(rentAmount > 0, "RET: No rent to claim");
        
        rentClaims[propertyId][distributionIndex][msg.sender] = true;
        lastRentClaimIndex[propertyId][msg.sender] = distributionIndex;
        
        _safeTransfer(msg.sender, rentAmount);
        
        emit RentClaimed(propertyId, msg.sender, rentAmount);
    }

    function claimAllRent(uint256 propertyId) public nonReentrant 
        validProperty(propertyId) propertyActive(propertyId) {
        require(propertyShareholdings[propertyId][msg.sender] > 0, "RET: No shares owned");
        
        uint256 totalClaimable = 0;
        uint256 userShares = propertyShareholdings[propertyId][msg.sender];
        uint256 soldShares = properties[propertyId].totalShares - properties[propertyId].availableShares;
        uint256 lastClaimed = lastRentClaimIndex[propertyId][msg.sender];
        
        for (uint256 i = lastClaimed; i < rentDistributions[propertyId].length; i++) {
            if (!rentClaims[propertyId][i][msg.sender]) {
                uint256 rentAmount = (rentDistributions[propertyId][i].totalRent * userShares) / soldShares;
                if (rentAmount > 0) {
                    totalClaimable += rentAmount;
                    rentClaims[propertyId][i][msg.sender] = true;
                }
            }
        }
        
        require(totalClaimable > 0, "RET: No rent to claim");
        lastRentClaimIndex[propertyId][msg.sender] = rentDistributions[propertyId].length;
        
        _safeTransfer(msg.sender, totalClaimable);
        
        emit RentClaimed(propertyId, msg.sender, totalClaimable);
    }

    function updatePropertyMetadata(
        uint256 propertyId,
        string memory description,
        string memory propertyType
    ) public validProperty(propertyId) onlyPropertyOwner(propertyId) {
        properties[propertyId].description = description;
        properties[propertyId].propertyType = propertyType;
        
        emit PropertyMetadataUpdated(propertyId, description, propertyType);
    }

    function transferPropertyOwnership(uint256 propertyId, address newOwner) public 
        validProperty(propertyId) onlyPropertyOwner(propertyId) {
        require(newOwner != address(0), "RET: Invalid new owner");
        require(properties[propertyId].propertyOwner != newOwner, "RET: Already owner");
        
        properties[propertyId].propertyOwner = newOwner;
        emit PropertyOwnerUpdated(propertyId, newOwner);
    }

    // ============ ENHANCED VIEW FUNCTIONS ============

    /**
     * @dev Get property shareholders with pagination
     */
    function getPropertyShareholders(uint256 propertyId, uint256 start, uint256 limit) 
        public 
        view 
        returns (address[] memory, uint256[] memory, uint256) 
    {
        Shareholder[] memory shareholders = propertyShareholders[propertyId];
        uint256 total = shareholders.length;
        
        if (start >= total) {
            return (new address[](0), new uint256[](0), total);
        }
        
        uint256 end = start + limit;
        if (end > total) {
            end = total;
        }
        
        uint256 resultCount = end - start;
        address[] memory addresses = new address[](resultCount);
        uint256[] memory shareAmounts = new uint256[](resultCount);
        
        for (uint256 i = start; i < end; i++) {
            addresses[i - start] = shareholders[i].shareholder;
            shareAmounts[i - start] = shareholders[i].shares;
        }
        
        return (addresses, shareAmounts, total);
    }

    /**
     * @dev Get user's dividend history
     */
    function getUserDividendHistory(address user, uint256 propertyId) public view returns (
        uint256[] memory timestamps,
        uint256[] memory amounts,
        bool[] memory claimed,
        uint256 totalClaimable
    ) {
        uint256 distributionCount = rentDistributions[propertyId].length;
        timestamps = new uint256[](distributionCount);
        amounts = new uint256[](distributionCount);
        claimed = new bool[](distributionCount);
        
        uint256 userShares = propertyShareholdings[propertyId][user];
        uint256 soldShares = properties[propertyId].totalShares - properties[propertyId].availableShares;
        totalClaimable = 0;
        
        for (uint256 i = 0; i < distributionCount; i++) {
            timestamps[i] = rentDistributions[propertyId][i].timestamp;
            amounts[i] = (rentDistributions[propertyId][i].totalRent * userShares) / soldShares;
            claimed[i] = rentClaims[propertyId][i][user];
            
            if (!claimed[i]) {
                totalClaimable += amounts[i];
            }
        }
        
        return (timestamps, amounts, claimed, totalClaimable);
    }

    /**
     * @dev Get market overview statistics
     */
    function getMarketOverview() public view returns (
        uint256 totalProperties,
        uint256 activeProperties,
        uint256 totalVolume,
        uint256 totalRentDistributed,
        uint256 totalInvestors
    ) {
        totalProperties = _tokenIdCounter.current();
        uint256 volume = 0;
        uint256 rent = 0;
        
        // Use a set-like approach to count unique investors
        address[] memory seenInvestors = new address[](100); // Simplified
        
        for (uint256 i = 0; i < totalProperties; i++) {
            if (properties[i].isActive) {
                activeProperties++;
                volume += properties[i].totalInvestment;
                rent += properties[i].totalRentDistributed;
            }
        }
        
        // For a more accurate investor count, you might want to maintain a separate mapping
        // This is a simplified version
        totalInvestors = _estimateUniqueInvestors();
        
        return (totalProperties, activeProperties, volume, rent, totalInvestors);
    }

    /**
     * @dev Estimate unique investors (simplified)
     */
    function _estimateUniqueInvestors() internal view returns (uint256) {
        // This is a simplified implementation
        // In production, you'd maintain a separate mapping of unique investors
        return _tokenIdCounter.current() * 3; // Rough estimate
    }

    /**
     * @dev Get user portfolio summary
     */
    function getUserPortfolio(address user) public view returns (
        uint256 totalProperties,
        uint256 totalInvestment,
        uint256 estimatedValue,
        uint256 totalDividends
    ) {
        uint256[] memory userProps = userProperties[user];
        totalProperties = userProps.length;
        totalInvestment = totalUserInvestment[user];
        estimatedValue = 0;
        totalDividends = 0;
        
        for (uint256 i = 0; i < userProps.length; i++) {
            uint256 propId = userProps[i];
            uint256 shares = propertyShareholdings[propId][user];
            if (shares > 0) {
                estimatedValue += shares * properties[propId].pricePerShare;
                
                // Calculate unclaimed dividends
                uint256 soldShares = properties[propId].totalShares - properties[propId].availableShares;
                for (uint256 j = 0; j < rentDistributions[propId].length; j++) {
                    if (!rentClaims[propId][j][user]) {
                        totalDividends += (rentDistributions[propId][j].totalRent * shares) / soldShares;
                    }
                }
            }
        }
        
        return (totalProperties, totalInvestment, estimatedValue, totalDividends);
    }

    // ============ OVERRIDE FUNCTIONS ============
    
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }
    
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _increaseBalance(address account, uint128 amount) internal override(ERC721) {
        super._increaseBalance(account, amount);
    }

    // ============ INTERNAL HELPER FUNCTIONS ============
    
    function _hasUserProperty(address user, uint256 propertyId) internal view returns (bool) {
        for (uint256 i = 0; i < userProperties[user].length; i++) {
            if (userProperties[user][i] == propertyId) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Get property details
     */
    function getPropertyDetails(uint256 propertyId) public view validProperty(propertyId) returns (
        string memory propertyAddress,
        string memory description,
        uint256 totalValue,
        uint256 totalShares,
        uint256 availableShares,
        uint256 pricePerShare,
        address propertyOwner,
        bool isActive,
        bool isPaused,
        string memory propertyType,
        uint256 squareFootage,
        uint256 totalInvestment,
        uint256 totalRentDistributed
    ) {
        Property storage property = properties[propertyId];
        return (
            property.propertyAddress,
            property.description,
            property.totalValue,
            property.totalShares,
            property.availableShares,
            property.pricePerShare,
            property.propertyOwner,
            property.isActive,
            property.isPaused,
            property.propertyType,
            property.squareFootage,
            property.totalInvestment,
            property.totalRentDistributed
        );
    }
}
