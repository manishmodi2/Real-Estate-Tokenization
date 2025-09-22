// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Real Estate Tokenization Contract
 * @dev A contract for tokenizing real estate properties as NFTs with fractional ownership capabilities
 */
contract RealEstateTokenization is ERC721, ERC721URIStorage, Ownable, ReentrancyGuard {
    uint256 private _tokenIdCounter;
    
    struct Property {
        uint256 tokenId;
        string propertyAddress;
        uint256 totalValue;
        uint256 totalShares;
        uint256 availableShares;
        uint256 pricePerShare;
        address propertyOwner;
        bool isActive;
        bool isPaused;
        uint256 creationTime;
        uint256 rentPerShare;
    }
    
    struct SharePurchase {
        uint256 propertyId;
        address buyer;
        uint256 shares;
        uint256 totalCost;
        uint256 timestamp;
    }

    struct RentDistribution {
        uint256 propertyId;
        uint256 totalRent;
        uint256 timestamp;
    }
    
    mapping(uint256 => Property) public properties;
    mapping(uint256 => SharePurchase[]) public propertyPurchases;
    mapping(address => uint256[]) public userProperties;
    mapping(uint256 => RentDistribution[]) public rentDistributions;
    
    // Separate mappings to replace struct mappings
    mapping(uint256 => mapping(address => uint256)) public propertyShareholdings;
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) public rentClaims;
    
    // Fee structure
    uint256 public platformFeePercentage = 250; // 2.5% (basis points)
    uint256 public constant MAX_FEE = 1000; // 10% maximum
    address public feeRecipient;
    
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
    
    constructor() ERC721("RealEstateTokens", "RET") Ownable(msg.sender) {
        feeRecipient = msg.sender;
    }
    
    /**
     * @dev Tokenize a real estate property as an NFT with fractional ownership
     * @param propertyAddress The physical address of the property
     * @param totalValue The total value of the property in wei
     * @param totalShares The total number of shares to divide the property into
     * @param metadataURI The metadata URI for the property NFT
     */
    function tokenizeProperty(
        string memory propertyAddress,
        uint256 totalValue,
        uint256 totalShares,
        string memory metadataURI
    ) public nonReentrant returns (uint256) {
        require(bytes(propertyAddress).length > 0, "RET: Property address cannot be empty");
        require(totalValue > 0, "RET: Total value must be greater than 0");
        require(totalShares > 0, "RET: Total shares must be greater than 0");
        require(totalValue >= totalShares, "RET: Value must be at least equal to shares");
        
        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;
        
        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, metadataURI);
        
        Property storage newProperty = properties[tokenId];
        newProperty.tokenId = tokenId;
        newProperty.propertyAddress = propertyAddress;
        newProperty.totalValue = totalValue;
        newProperty.totalShares = totalShares;
        newProperty.availableShares = totalShares;
        newProperty.pricePerShare = totalValue / totalShares;
        newProperty.propertyOwner = msg.sender;
        newProperty.isActive = true;
        newProperty.isPaused = false;
        newProperty.creationTime = block.timestamp;
        newProperty.rentPerShare = 0;
        
        // Initialize shareholdings for property owner
        propertyShareholdings[tokenId][msg.sender] = 0; // Owner doesn't automatically get shares
        
        userProperties[msg.sender].push(tokenId);
        
        emit PropertyTokenized(tokenId, propertyAddress, totalValue, totalShares, msg.sender);
        
        return tokenId;
    }
    
    /**
     * @dev Purchase shares of a tokenized property
     * @param propertyId The ID of the property to purchase shares from
     * @param shares The number of shares to purchase
     */
    function purchaseShares(
        uint256 propertyId, 
        uint256 shares
    ) public payable nonReentrant 
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
        
        // Record the purchase
        propertyPurchases[propertyId].push(SharePurchase({
            propertyId: propertyId,
            buyer: msg.sender,
            shares: shares,
            totalCost: totalCost,
            timestamp: block.timestamp
        }));
        
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
     * @dev Transfer shares between users
     * @param propertyId The ID of the property
     * @param to The address to transfer shares to
     * @param shares The number of shares to transfer
     */
    function transferShares(
        uint256 propertyId, 
        address to, 
        uint256 shares
    ) public nonReentrant 
      validProperty(propertyId)
      propertyActive(propertyId)
      propertyNotPaused(propertyId)
    {
        require(to != address(0), "RET: Cannot transfer to zero address");
        require(to != msg.sender, "RET: Cannot transfer to yourself");
        require(shares > 0, "RET: Shares must be greater than 0");
        require(propertyShareholdings[propertyId][msg.sender] >= shares, "RET: Insufficient shares");
        
        // Update shareholdings
        propertyShareholdings[propertyId][msg.sender] -= shares;
        propertyShareholdings[propertyId][to] += shares;
        
        // Add to recipient's property list if first time
        if (!hasUserProperty(to, propertyId)) {
            userProperties[to].push(propertyId);
        }
        
        emit SharesTransferred(propertyId, msg.sender, to, shares);
    }

    /**
     * @dev Pause/unpause trading for a specific property (only property owner)
     * @param propertyId The ID of the property
     * @param isPaused Whether to pause or unpause
     */
    function pauseProperty(
        uint256 propertyId, 
        bool isPaused
    ) public 
      validProperty(propertyId)
      onlyPropertyOwner(propertyId)
      propertyActive(propertyId)
    {
        properties[propertyId].isPaused = isPaused;
        emit PropertyPaused(propertyId, isPaused);
    }

    /**
     * @dev Update property value (only property owner)
     * @param propertyId The ID of the property
     * @param newValue The new total value of the property
     */
    function updatePropertyValue(
        uint256 propertyId, 
        uint256 newValue
    ) public 
      validProperty(propertyId)
      onlyPropertyOwner(propertyId)
      propertyActive(propertyId)
    {
        require(newValue > 0, "RET: New value must be greater than 0");
        
        Property storage property = properties[propertyId];
        uint256 oldValue = property.totalValue;
        property.totalValue = newValue;
        property.pricePerShare = newValue / property.totalShares;
        
        emit PropertyValueUpdated(propertyId, oldValue, newValue);
    }

    /**
     * @dev Distribute rental income to shareholders
     * @param propertyId The ID of the property
     */
    function distributeRent(
        uint256 propertyId
    ) public payable 
      validProperty(propertyId)
      onlyPropertyOwner(propertyId)
      propertyActive(propertyId)
    {
        require(msg.value > 0, "RET: Rent amount must be greater than 0");
        
        Property storage property = properties[propertyId];
        uint256 soldShares = property.totalShares - property.availableShares;
        require(soldShares > 0, "RET: No shares sold yet");
        
        RentDistribution memory newDistribution = RentDistribution({
            propertyId: propertyId,
            totalRent: msg.value,
            timestamp: block.timestamp
        });
        
        rentDistributions[propertyId].push(newDistribution);
        
        // Calculate rent per share for this distribution
        property.rentPerShare = msg.value / soldShares;
        
        emit RentDistributed(propertyId, msg.value, block.timestamp);
    }

    /**
     * @dev Claim rental income for a specific distribution
     * @param propertyId The ID of the property
     * @param distributionIndex The index of the rent distribution
     */
    function claimRent(
        uint256 propertyId, 
        uint256 distributionIndex
    ) public nonReentrant 
      validProperty(propertyId)
      propertyActive(propertyId)
    {
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
        payable(msg.sender).transfer(rentAmount);
        
        emit RentClaimed(propertyId, msg.sender, rentAmount);
    }

    /**
     * @dev Batch claim rent for multiple distributions
     * @param propertyId The ID of the property
     * @param distributionIndices Array of distribution indices to claim
     */
    function batchClaimRent(
        uint256 propertyId, 
        uint256[] memory distributionIndices
    ) public nonReentrant 
      validProperty(propertyId)
      propertyActive(propertyId)
    {
        require(propertyShareholdings[propertyId][msg.sender] > 0, "RET: No shares owned");
        require(distributionIndices.length > 0, "RET: No distributions specified");
        
        Property storage property = properties[propertyId];
        uint256 userShares = propertyShareholdings[propertyId][msg.sender];
        uint256 soldShares = property.totalShares - property.availableShares;
        uint256 totalRentAmount = 0;
        
        for (uint256 i = 0; i < distributionIndices.length; i++) {
            uint256 distributionIndex = distributionIndices[i];
            require(distributionIndex < rentDistributions[propertyId].length, "RET: Invalid distribution index");
            
            if (!rentClaims[propertyId][distributionIndex][msg.sender]) {
                RentDistribution storage distribution = rentDistributions[propertyId][distributionIndex];
                uint256 rentAmount = (distribution.totalRent * userShares) / soldShares;
                
                rentClaims[propertyId][distributionIndex][msg.sender] = true;
                totalRentAmount += rentAmount;
                
                emit RentClaimed(propertyId, msg.sender, rentAmount);
            }
        }
        
        require(totalRentAmount > 0, "RET: No rent to claim");
        payable(msg.sender).transfer(totalRentAmount);
    }

    /**
     * @dev Deactivate a property (only property owner)
     * @param propertyId The ID of the property
     */
    function deactivateProperty(
        uint256 propertyId
    ) public 
      validProperty(propertyId)
      onlyPropertyOwner(propertyId)
      propertyActive(propertyId)
    {
        Property storage property = properties[propertyId];
        
        // Allow deactivation only if no shares are sold or all shareholders agree (simplified)
        require(property.availableShares == property.totalShares, 
            "RET: Cannot deactivate property with active shareholders");
        
        property.isActive = false;
        emit PropertyDeactivated(propertyId);
    }

    /**
     * @dev Emergency withdrawal function (only owner) - for stuck funds
     */
    function emergencyWithdraw() public onlyOwner {
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0, "RET: No funds to withdraw");
        
        payable(owner()).transfer(contractBalance);
    }

    /**
     * @dev Set platform fee (only owner)
     * @param newFeePercentage New fee percentage in basis points (e.g., 250 = 2.5%)
     */
    function setPlatformFee(uint256 newFeePercentage) public onlyOwner {
        require(newFeePercentage <= MAX_FEE, "RET: Fee too high");
        
        uint256 oldFee = platformFeePercentage;
        platformFeePercentage = newFeePercentage;
        
        emit PlatformFeeUpdated(oldFee, newFeePercentage);
    }

    /**
     * @dev Set fee recipient address (only owner)
     * @param newFeeRecipient New fee recipient address
     */
    function setFeeRecipient(address newFeeRecipient) public onlyOwner {
        require(newFeeRecipient != address(0), "RET: Invalid address");
        feeRecipient = newFeeRecipient;
    }

    // ============ VIEW FUNCTIONS ============

    /**
     * @dev Get complete property details
     */
    function getPropertyDetails(uint256 propertyId) public view returns (
        string memory propertyAddress,
        uint256 totalValue,
        uint256 totalShares,
        uint256 availableShares,
        uint256 pricePerShare,
        address propertyOwner,
        bool isActive,
        bool isPaused,
        uint256 creationTime,
        uint256 rentPerShare
    ) {
        Property storage property = properties[propertyId];
        require(property.tokenId == propertyId, "RET: Invalid property ID");
        
        return (
            property.propertyAddress,
            property.totalValue,
            property.totalShares,
            property.availableShares,
            property.pricePerShare,
            property.propertyOwner,
            property.isActive,
            property.isPaused,
            property.creationTime,
            property.rentPerShare
        );
    }
    
    function getUserShares(uint256 propertyId, address user) public view returns (uint256) {
        return propertyShareholdings[propertyId][user];
    }
    
    function getUserProperties(address user) public view returns (uint256[] memory) {
        return userProperties[user];
    }
    
    function getPropertyPurchases(uint256 propertyId) public view returns (uint256) {
        return propertyPurchases[propertyId].length;
    }
    
    function getPurchaseDetails(uint256 propertyId, uint256 index) public view returns (
        address buyer,
        uint256 shares,
        uint256 totalCost,
        uint256 timestamp
    ) {
        require(index < propertyPurchases[propertyId].length, "RET: Invalid purchase index");
        SharePurchase memory purchase = propertyPurchases[propertyId][index];
        return (purchase.buyer, purchase.shares, purchase.totalCost, purchase.timestamp);
    }
    
    function getTotalProperties() public view returns (uint256) {
        return _tokenIdCounter;
    }

    /**
     * @dev Get rent distribution count for a property
     */
    function getRentDistributionCount(uint256 propertyId) public view returns (uint256) {
        return rentDistributions[propertyId].length;
    }

    /**
     * @dev Get rent distribution details
     */
    function getRentDistribution(uint256 propertyId, uint256 index) public view returns (
        uint256 totalRent,
        uint256 timestamp
    ) {
        require(index < rentDistributions[propertyId].length, "RET: Invalid distribution index");
        RentDistribution memory distribution = rentDistributions[propertyId][index];
        return (distribution.totalRent, distribution.timestamp);
    }

    /**
     * @dev Check if user has claimed rent for a specific distribution
     */
    function hasClaimedRent(uint256 propertyId, uint256 distributionIndex, address user) public view returns (bool) {
        require(distributionIndex < rentDistributions[propertyId].length, "RET: Invalid distribution index");
        return rentClaims[propertyId][distributionIndex][user];
    }

    /**
     * @dev Get unclaimed rent amount for a user
     */
    function getUnclaimedRent(uint256 propertyId, address user) public view returns (uint256) {
        Property storage property = properties[propertyId];
        uint256 userShares = propertyShareholdings[propertyId][user];
        
        if (userShares == 0) return 0;
        
        uint256 totalUnclaimed = 0;
        uint256 soldShares = property.totalShares - property.availableShares;
        
        for (uint256 i = 0; i < rentDistributions[propertyId].length; i++) {
            if (!rentClaims[propertyId][i][user]) {
                RentDistribution storage distribution = rentDistributions[propertyId][i];
                uint256 rentAmount = (distribution.totalRent * userShares) / soldShares;
                totalUnclaimed += rentAmount;
            }
        }
        
        return totalUnclaimed;
    }

    /**
     * @dev Get comprehensive property statistics
     */
    function getPropertyStats(uint256 propertyId) public view returns (
        uint256 totalInvestors,
        uint256 totalRentDistributed,
        uint256 totalTransactions,
        uint256 occupancyRate,
        uint256 totalVolume
    ) {
        Property storage property = properties[propertyId];
        require(property.tokenId == propertyId, "RET: Invalid property ID");
        
        // Count unique investors
        address[] memory investors = new address[](propertyPurchases[propertyId].length);
        uint256 uniqueInvestorCount = 0;
        uint256 volume = 0;
        
        for (uint256 i = 0; i < propertyPurchases[propertyId].length; i++) {
            address buyer = propertyPurchases[propertyId][i].buyer;
            volume += propertyPurchases[propertyId][i].totalCost;
            
            bool isUnique = true;
            for (uint256 j = 0; j < uniqueInvestorCount; j++) {
                if (investors[j] == buyer) {
                    isUnique = false;
                    break;
                }
            }
            
            if (isUnique) {
                investors[uniqueInvestorCount] = buyer;
                uniqueInvestorCount++;
            }
        }
        
        // Calculate total rent distributed
        uint256 totalRent = 0;
        for (uint256 i = 0; i < rentDistributions[propertyId].length; i++) {
            totalRent += rentDistributions[propertyId][i].totalRent;
        }
        
        // Calculate occupancy rate (in basis points)
        uint256 soldShares = property.totalShares - property.availableShares;
        uint256 occupancy = property.totalShares > 0 ? (soldShares * 10000) / property.totalShares : 0;
        
        return (
            uniqueInvestorCount,
            totalRent,
            propertyPurchases[propertyId].length,
            occupancy,
            volume
        );
    }

    /**
     * @dev Get user's portfolio summary
     */
    function getUserPortfolio(address user) public view returns (
        uint256 totalProperties,
        uint256 totalInvestment,
        uint256 unclaimedRent,
        uint256 currentPortfolioValue
    ) {
        uint256[] memory userProps = userProperties[user];
        uint256 investment = 0;
        uint256 rent = 0;
        uint256 portfolioValue = 0;
        
        for (uint256 i = 0; i < userProps.length; i++) {
            uint256 propertyId = userProps[i];
            uint256 userShares = propertyShareholdings[propertyId][user];
            
            if (userShares > 0) {
                Property storage property = properties[propertyId];
                investment += getUserInvestmentInProperty(propertyId, user);
                rent += getUnclaimedRent(propertyId, user);
                portfolioValue += userShares * property.pricePerShare;
            }
        }
        
        return (userProps.length, investment, rent, portfolioValue);
    }

    /**
     * @dev Get user's investment in a specific property
     */
    function getUserInvestmentInProperty(uint256 propertyId, address user) public view returns (uint256) {
        uint256 totalInvestment = 0;
        
        for (uint256 i = 0; i < propertyPurchases[propertyId].length; i++) {
            if (propertyPurchases[propertyId][i].buyer == user) {
                totalInvestment += propertyPurchases[propertyId][i].totalCost;
            }
        }
        
        return totalInvestment;
    }

    // ============ INTERNAL HELPER FUNCTIONS ============
    
    /**
     * @dev Check if user already has a property in their list
     */
    function hasUserProperty(address user, uint256 propertyId) internal view returns (bool) {
        for (uint256 i = 0; i < userProperties[user].length; i++) {
            if (userProperties[user][i] == propertyId) {
                return true;
            }
        }
        return false;
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
}
