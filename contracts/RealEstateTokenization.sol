// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title Real Estate Tokenization Contract
 * @dev A contract for tokenizing real estate properties as NFTs with fractional ownership capabilities
 */
contract RealEstateTokenization is ERC721, ERC721URIStorage, Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
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
    }
    
    mapping(uint256 => Property) public properties;
    mapping(uint256 => SharePurchase[]) public propertyPurchases;
    mapping(address => uint256[]) public userProperties;
    mapping(uint256 => RentDistribution[]) public rentDistributions;
    mapping(uint256 => Shareholder[]) public propertyShareholders;
    
    // Separate mappings to replace struct mappings
    mapping(uint256 => mapping(address => uint256)) public propertyShareholdings;
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) public rentClaims;
    mapping(uint256 => mapping(address => uint256)) public userInvestment;
    mapping(uint256 => mapping(address => uint256)) public lastRentClaimIndex;
    
    // Fee structure
    uint256 public platformFeePercentage = 250; // 2.5% (basis points)
    uint256 public constant MAX_FEE = 1000; // 10% maximum
    address public feeRecipient;

    // Voting system for major decisions
    struct Vote {
        uint256 propertyId;
        string proposal;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 endTime;
        bool executed;
        mapping(address => bool) hasVoted;
        mapping(address => uint256) votesCast;
    }
    
    Vote[] public votes;
    uint256 public constant VOTING_DURATION = 7 days;
    uint256 public constant QUORUM_PERCENTAGE = 51; // 51% required
    
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
        uint256 totalCost
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
    
    event PropertyDeactivated(uint256 indexed propertyId);

    event VoteCreated(uint256 indexed voteId, uint256 propertyId, string proposal);
    event VoteCast(uint256 indexed voteId, address voter, bool support, uint256 shares);
    event VoteExecuted(uint256 indexed voteId, bool passed);
    
    event PropertyMetadataUpdated(uint256 indexed propertyId, string description, string propertyType);
    event EmergencyStop(bool stopped);
    event FundsRecovered(address token, uint256 amount);

    // Modifiers for better readability
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

    bool public emergencyStop = false;
    modifier notInEmergency() {
        require(!emergencyStop, "RET: Contract in emergency stop");
        _;
    }
    
    constructor() ERC721("RealEstateTokens", "RET") Ownable(msg.sender) {
        feeRecipient = msg.sender;
    }
    
    /**
     * @dev Tokenize a real estate property as an NFT with fractional ownership
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
        
        userProperties[msg.sender].push(tokenId);
        
        emit PropertyTokenized(tokenId, propertyAddress, totalValue, totalShares, msg.sender);
        
        return tokenId;
    }
    
    /**
     * @dev Purchase shares of a tokenized property
     */
    function purchaseShares(
        uint256 propertyId, 
        uint256 shares
    ) public payable nonReentrant notInEmergency
      validProperty(propertyId)
      propertyActive(propertyId)
      propertyNotPaused(propertyId) 
    {
        Property storage property = properties[propertyId];
        
        require(shares > 0, "RET: Shares must be greater than 0");
        require(shares <= property.availableShares, "RET: Not enough shares available");
        
        uint256 totalCost = shares * property.pricePerShare;
        require(msg.value >= totalCost, "RET: Insufficient payment");
        
        // Calculate platform fee
        uint256 platformFee = (totalCost * platformFeePercentage) / 10000;
        uint256 ownerPayment = totalCost - platformFee;
        
        // Update property shareholdings
        propertyShareholdings[propertyId][msg.sender] += shares;
        property.availableShares -= shares;
        userInvestment[propertyId][msg.sender] += totalCost;
        
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
        if (!hasUserProperty(msg.sender, propertyId)) {
            userProperties[msg.sender].push(propertyId);
        }
        
        // Transfer payments
        if (ownerPayment > 0) {
            payable(property.propertyOwner).transfer(ownerPayment);
        }
        if (platformFee > 0) {
            payable(feeRecipient).transfer(platformFee);
        }
        
        // Refund excess payment
        if (msg.value > totalCost) {
            payable(msg.sender).transfer(msg.value - totalCost);
        }
        
        emit SharesPurchased(propertyId, msg.sender, shares, totalCost);
    }

    /**
     * @dev Bulk purchase shares for multiple properties
     */
    function bulkPurchaseShares(
        uint256[] memory propertyIds,
        uint256[] memory shares
    ) public payable nonReentrant notInEmergency {
        require(propertyIds.length == shares.length, "RET: Arrays length mismatch");
        require(propertyIds.length > 0, "RET: No properties specified");
        
        uint256 totalCost = 0;
        
        // Calculate total cost first
        for (uint256 i = 0; i < propertyIds.length; i++) {
            Property storage property = properties[propertyIds[i]];
            require(property.isActive && !property.isPaused, "RET: Property not available");
            require(shares[i] <= property.availableShares, "RET: Not enough shares available");
            totalCost += shares[i] * property.pricePerShare;
        }
        
        require(msg.value >= totalCost, "RET: Insufficient payment");
        
        // Execute purchases
        for (uint256 i = 0; i < propertyIds.length; i++) {
            if (shares[i] > 0) {
                // Use internal function to avoid reentrancy and re-checking
                _purchaseSharesInternal(propertyIds[i], shares[i], msg.sender);
            }
        }
        
        // Refund excess payment
        if (msg.value > totalCost) {
            payable(msg.sender).transfer(msg.value - totalCost);
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
        
        // Update shareholdings
        propertyShareholdings[propertyId][buyer] += shares;
        property.availableShares -= shares;
        userInvestment[propertyId][buyer] += totalCost;
        
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
        if (ownerPayment > 0) {
            payable(property.propertyOwner).transfer(ownerPayment);
        }
        if (platformFee > 0) {
            payable(feeRecipient).transfer(platformFee);
        }
        
        emit SharesPurchased(propertyId, buyer, shares, totalCost);
    }
    
    /**
     * @dev Transfer shares between users
     */
    function transferShares(
        uint256 propertyId, 
        address to, 
        uint256 shares
    ) public nonReentrant notInEmergency
      validProperty(propertyId)
      propertyActive(propertyId)
      propertyNotPaused(propertyId)
    {
        require(to != address(0), "RET: Cannot transfer to zero address");
        require(to != msg.sender, "RET: Cannot transfer to yourself");
        require(shares > 0, "RET: Shares must be greater than 0");
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

        // Update shareholders
        _updateShareholder(propertyId, msg.sender, shares, investmentTransferred, false);
        _updateShareholder(propertyId, to, shares, investmentTransferred, true);
        
        // Add to recipient's property list if first time
        if (!hasUserProperty(to, propertyId)) {
            userProperties[to].push(propertyId);
        }
        
        emit SharesTransferred(propertyId, msg.sender, to, shares);
    }

    /**
     * @dev Create a vote for property-related decisions
     */
    function createVote(
        uint256 propertyId,
        string memory proposal
    ) public validProperty(propertyId) onlyShareholder(propertyId) returns (uint256) {
        uint256 voteId = votes.length;
        
        Vote storage newVote = votes.push();
        newVote.propertyId = propertyId;
        newVote.proposal = proposal;
        newVote.endTime = block.timestamp + VOTING_DURATION;
        newVote.executed = false;
        
        emit VoteCreated(voteId, propertyId, proposal);
        return voteId;
    }

    /**
     * @dev Cast a vote
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
     */
    function executeVote(uint256 voteId) public notInEmergency {
        require(voteId < votes.length, "RET: Invalid vote ID");
        Vote storage vote = votes[voteId];
        require(block.timestamp > vote.endTime, "RET: Voting still active");
        require(!vote.executed, "RET: Vote already executed");
        
        vote.executed = true;
        
        uint256 totalVotes = vote.votesFor + vote.votesAgainst;
        uint256 totalShares = properties[vote.propertyId].totalShares - properties[vote.propertyId].availableShares;
        
        bool passed = (totalVotes * 100 >= totalShares * QUORUM_PERCENTAGE) && 
                     (vote.votesFor > vote.votesAgainst);
        
        // Here you could add logic to execute the proposal based on vote.proposal
        // For example: change property management, update fees, etc.
        
        emit VoteExecuted(voteId, passed);
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
                    propertyShareholders[propertyId][i].shares -= shares;
                    propertyShareholders[propertyId][i].investment -= investment;
                    
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
                lastClaimIndex: 0
            }));
        }
    }

    /**
     * @dev Emergency stop mechanism
     */
    function setEmergencyStop(bool stop) public onlyOwner {
        emergencyStop = stop;
        emit EmergencyStop(stop);
    }

    /**
     * @dev Recover accidentally sent tokens
     */
    function recoverTokens(address tokenAddress, uint256 amount) public onlyOwner {
        require(tokenAddress != address(0), "RET: Invalid token address");
        if (tokenAddress == address(0)) {
            payable(owner()).transfer(amount);
        } else {
            // For ERC20 tokens - you'd need IERC20 interface
            // IERC20(tokenAddress).transfer(owner(), amount);
        }
        emit FundsRecovered(tokenAddress, amount);
    }

    // ============ ENHANCED VIEW FUNCTIONS ============

    /**
     * @dev Get property shareholders
     */
    function getPropertyShareholders(uint256 propertyId) public view returns (address[] memory, uint256[] memory) {
        Shareholder[] memory shareholders = propertyShareholders[propertyId];
        address[] memory addresses = new address[](shareholders.length);
        uint256[] memory shareAmounts = new uint256[](shareholders.length);
        
        for (uint256 i = 0; i < shareholders.length; i++) {
            addresses[i] = shareholders[i].shareholder;
            shareAmounts[i] = shareholders[i].shares;
        }
        
        return (addresses, shareAmounts);
    }

    /**
     * @dev Get user's dividend history
     */
    function getUserDividendHistory(address user, uint256 propertyId) public view returns (
        uint256[] memory timestamps,
        uint256[] memory amounts,
        bool[] memory claimed
    ) {
        uint256 distributionCount = rentDistributions[propertyId].length;
        timestamps = new uint256[](distributionCount);
        amounts = new uint256[](distributionCount);
        claimed = new bool[](distributionCount);
        
        uint256 userShares = propertyShareholdings[propertyId][user];
        uint256 soldShares = properties[propertyId].totalShares - properties[propertyId].availableShares;
        
        for (uint256 i = 0; i < distributionCount; i++) {
            timestamps[i] = rentDistributions[propertyId][i].timestamp;
            amounts[i] = (rentDistributions[propertyId][i].totalRent * userShares) / soldShares;
            claimed[i] = rentClaims[propertyId][i][user];
        }
        
        return (timestamps, amounts, claimed);
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
        uint256 investorCount = 0;
        
        // Use a mapping to track unique investors across all properties
        address[] memory allInvestors = new address[](1000); // Simplified approach
        uint256 uniqueCount = 0;
        
        for (uint256 i = 0; i < totalProperties; i++) {
            if (properties[i].isActive) {
                activeProperties++;
                
                // Calculate volume for this property
                for (uint256 j = 0; j < propertyPurchases[i].length; j++) {
                    volume += propertyPurchases[i][j].totalCost;
                    
                    // Track unique investors
                    address investor = propertyPurchases[i][j].buyer;
                    bool isUnique = true;
                    for (uint256 k = 0; k < uniqueCount; k++) {
                        if (allInvestors[k] == investor) {
                            isUnique = false;
                            break;
                        }
                    }
                    if (isUnique && uniqueCount < allInvestors.length) {
                        allInvestors[uniqueCount] = investor;
                        uniqueCount++;
                    }
                }
                
                // Calculate total rent
                for (uint256 j = 0; j < rentDistributions[i].length; j++) {
                    rent += rentDistributions[i][j].totalRent;
                }
            }
        }
        
        return (totalProperties, activeProperties, volume, rent, uniqueCount);
    }

    // ============ EXISTING FUNCTIONS (with minor enhancements) ============
    
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
        payable(msg.sender).transfer(rentAmount);
        
        emit RentClaimed(propertyId, msg.sender, rentAmount);
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
    
    function hasUserProperty(address user, uint256 propertyId) internal view returns (bool) {
        for (uint256 i = 0; i < userProperties[user].length; i++) {
            if (userProperties[user][i] == propertyId) {
                return true;
            }
        }
        return false;
    }
}
