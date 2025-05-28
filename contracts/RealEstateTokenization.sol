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
contract Project is ERC721, ERC721URIStorage, Ownable, ReentrancyGuard {
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
        mapping(address => uint256) shareholdings;
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
        mapping(address => bool) claimed;
    }
    
    mapping(uint256 => Property) public properties;
    mapping(uint256 => SharePurchase[]) public propertyPurchases;
    mapping(address => uint256[]) public userProperties;
    mapping(uint256 => RentDistribution[]) public rentDistributions;
    mapping(uint256 => uint256) public propertyToRentIndex;
    
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
        require(bytes(propertyAddress).length > 0, "Property address cannot be empty");
        require(totalValue > 0, "Total value must be greater than 0");
        require(totalShares > 0, "Total shares must be greater than 0");
        
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
        
        userProperties[msg.sender].push(tokenId);
        
        emit PropertyTokenized(tokenId, propertyAddress, totalValue, totalShares, msg.sender);
        
        return tokenId;
    }
    
    /**
     * @dev Purchase shares of a tokenized property
     * @param propertyId The ID of the property to purchase shares from
     * @param shares The number of shares to purchase
     */
    function purchaseShares(uint256 propertyId, uint256 shares) public payable nonReentrant {
        Property storage property = properties[propertyId];
        
        require(property.isActive, "Property is not active");
        require(!property.isPaused, "Property trading is paused");
        require(shares > 0, "Shares must be greater than 0");
        require(shares <= property.availableShares, "Not enough shares available");
        
        uint256 totalCost = shares * property.pricePerShare;
        require(msg.value >= totalCost, "Insufficient payment");
        
        // Calculate platform fee
        uint256 platformFee = (totalCost * platformFeePercentage) / 10000;
        uint256 ownerPayment = totalCost - platformFee;
        
        // Update property shareholdings
        property.shareholdings[msg.sender] += shares;
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
        bool hasProperty = false;
        for (uint256 i = 0; i < userProperties[msg.sender].length; i++) {
            if (userProperties[msg.sender][i] == propertyId) {
                hasProperty = true;
                break;
            }
        }
        if (!hasProperty) {
            userProperties[msg.sender].push(propertyId);
        }
        
        // Transfer payments
        payable(property.propertyOwner).transfer(ownerPayment);
        payable(feeRecipient).transfer(platformFee);
        
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
    function transferShares(uint256 propertyId, address to, uint256 shares) public nonReentrant {
        Property storage property = properties[propertyId];
        
        require(property.isActive, "Property is not active");
        require(!property.isPaused, "Property trading is paused");
        require(to != address(0), "Cannot transfer to zero address");
        require(to != msg.sender, "Cannot transfer to yourself");
        require(shares > 0, "Shares must be greater than 0");
        require(property.shareholdings[msg.sender] >= shares, "Insufficient shares");
        
        // Update shareholdings
        property.shareholdings[msg.sender] -= shares;
        property.shareholdings[to] += shares;
        
        // Add to recipient's property list if first time
        bool hasProperty = false;
        for (uint256 i = 0; i < userProperties[to].length; i++) {
            if (userProperties[to][i] == propertyId) {
                hasProperty = true;
                break;
            }
        }
        if (!hasProperty) {
            userProperties[to].push(propertyId);
        }
        
        emit SharesTransferred(propertyId, msg.sender, to, shares);
    }

    /**
     * @dev Pause/unpause trading for a specific property (only property owner)
     * @param propertyId The ID of the property
     * @param isPaused Whether to pause or unpause
     */
    function pauseProperty(uint256 propertyId, bool isPaused) public {
        Property storage property = properties[propertyId];
        require(msg.sender == property.propertyOwner, "Only property owner can pause");
        require(property.isActive, "Property is not active");
        
        property.isPaused = isPaused;
        emit PropertyPaused(propertyId, isPaused);
    }

    /**
     * @dev Update property value (only property owner)
     * @param propertyId The ID of the property
     * @param newValue The new total value of the property
     */
    function updatePropertyValue(uint256 propertyId, uint256 newValue) public {
        Property storage property = properties[propertyId];
        require(msg.sender == property.propertyOwner, "Only property owner can update value");
        require(property.isActive, "Property is not active");
        require(newValue > 0, "New value must be greater than 0");
        
        uint256 oldValue = property.totalValue;
        property.totalValue = newValue;
        property.pricePerShare = newValue / property.totalShares;
        
        emit PropertyValueUpdated(propertyId, oldValue, newValue);
    }

    /**
     * @dev Distribute rental income to shareholders
     * @param propertyId The ID of the property
     */
    function distributeRent(uint256 propertyId) public payable {
        Property storage property = properties[propertyId];
        require(msg.sender == property.propertyOwner, "Only property owner can distribute rent");
        require(property.isActive, "Property is not active");
        require(msg.value > 0, "Rent amount must be greater than 0");
        
        uint256 rentIndex = rentDistributions[propertyId].length;
        rentDistributions[propertyId].push();
        RentDistribution storage newDistribution = rentDistributions[propertyId][rentIndex];
        
        newDistribution.propertyId = propertyId;
        newDistribution.totalRent = msg.value;
        newDistribution.timestamp = block.timestamp;
        
        property.rentPerShare = msg.value / (property.totalShares - property.availableShares);
        
        emit RentDistributed(propertyId, msg.value, block.timestamp);
    }

    /**
     * @dev Claim rental income for a specific distribution
     * @param propertyId The ID of the property
     * @param distributionIndex The index of the rent distribution
     */
    function claimRent(uint256 propertyId, uint256 distributionIndex) public nonReentrant {
        Property storage property = properties[propertyId];
        require(property.isActive, "Property is not active");
        require(distributionIndex < rentDistributions[propertyId].length, "Invalid distribution index");
        require(property.shareholdings[msg.sender] > 0, "No shares owned");
        
        RentDistribution storage distribution = rentDistributions[propertyId][distributionIndex];
        require(!distribution.claimed[msg.sender], "Rent already claimed");
        
        uint256 userShares = property.shareholdings[msg.sender];
        uint256 totalOwnedShares = property.totalShares - property.availableShares;
        uint256 rentAmount = (distribution.totalRent * userShares) / totalOwnedShares;
        
        distribution.claimed[msg.sender] = true;
        payable(msg.sender).transfer(rentAmount);
        
        emit RentClaimed(propertyId, msg.sender, rentAmount);
    }

    /**
     * @dev Batch claim rent for multiple distributions
     * @param propertyId The ID of the property
     * @param distributionIndices Array of distribution indices to claim
     */
    function batchClaimRent(uint256 propertyId, uint256[] memory distributionIndices) public nonReentrant {
        Property storage property = properties[propertyId];
        require(property.isActive, "Property is not active");
        require(property.shareholdings[msg.sender] > 0, "No shares owned");
        
        uint256 totalRentAmount = 0;
        uint256 userShares = property.shareholdings[msg.sender];
        
        for (uint256 i = 0; i < distributionIndices.length; i++) {
            uint256 distributionIndex = distributionIndices[i];
            require(distributionIndex < rentDistributions[propertyId].length, "Invalid distribution index");
            
            RentDistribution storage distribution = rentDistributions[propertyId][distributionIndex];
            if (!distribution.claimed[msg.sender]) {
                uint256 totalOwnedShares = property.totalShares - property.availableShares;
                uint256 rentAmount = (distribution.totalRent * userShares) / totalOwnedShares;
                
                distribution.claimed[msg.sender] = true;
                totalRentAmount += rentAmount;
                
                emit RentClaimed(propertyId, msg.sender, rentAmount);
            }
        }
        
        require(totalRentAmount > 0, "No rent to claim");
        payable(msg.sender).transfer(totalRentAmount);
    }

    /**
     * @dev Deactivate a property (only property owner)
     * @param propertyId The ID of the property
     */
    function deactivateProperty(uint256 propertyId) public {
        Property storage property = properties[propertyId];
        require(msg.sender == property.propertyOwner, "Only property owner can deactivate");
        require(property.isActive, "Property is already inactive");
        
        property.isActive = false;
    }

    /**
     * @dev Emergency withdrawal function (only owner)
     * @param propertyId The ID of the property
     */
    function emergencyWithdraw(uint256 propertyId) public onlyOwner {
        Property storage property = properties[propertyId];
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0, "No funds to withdraw");
        
        payable(owner()).transfer(contractBalance);
    }

    /**
     * @dev Set platform fee (only owner)
     * @param newFeePercentage New fee percentage in basis points (e.g., 250 = 2.5%)
     */
    function setPlatformFee(uint256 newFeePercentage) public onlyOwner {
        require(newFeePercentage <= MAX_FEE, "Fee too high");
        
        uint256 oldFee = platformFeePercentage;
        platformFeePercentage = newFeePercentage;
        
        emit PlatformFeeUpdated(oldFee, newFeePercentage);
    }

    /**
     * @dev Set fee recipient address (only owner)
     * @param newFeeRecipient New fee recipient address
     */
    function setFeeRecipient(address newFeeRecipient) public onlyOwner {
        require(newFeeRecipient != address(0), "Invalid address");
        feeRecipient = newFeeRecipient;
    }

    // View functions
    function getPropertyDetails(uint256 propertyId) public view returns (
        string memory propertyAddress,
        uint256 totalValue,
        uint256 totalShares,
        uint256 availableShares,
        uint256 pricePerShare,
        address propertyOwner,
        bool isActive,
        bool isPaused,
        uint256 creationTime
    ) {
        Property storage property = properties[propertyId];
        return (
            property.propertyAddress,
            property.totalValue,
            property.totalShares,
            property.availableShares,
            property.pricePerShare,
            property.propertyOwner,
            property.isActive,
            property.isPaused,
            property.creationTime
        );
    }
    
    function getUserShares(uint256 propertyId, address user) public view returns (uint256) {
        return properties[propertyId].shareholdings[user];
    }
    
    function getUserProperties(address user) public view returns (uint256[] memory) {
        return userProperties[user];
    }
    
    function getPropertyPurchases(uint256 propertyId) public view returns (uint256) {
        return propertyPurchases[propertyId].length;
    }
    
    function getTotalProperties() public view returns (uint256) {
        return _tokenIdCounter;
    }

    /**
     * @dev Get rent distribution count for a property
     * @param propertyId The ID of the property
     */
    function getRentDistributionCount(uint256 propertyId) public view returns (uint256) {
        return rentDistributions[propertyId].length;
    }

    /**
     * @dev Check if user has claimed rent for a specific distribution
     * @param propertyId The ID of the property
     * @param distributionIndex The distribution index
     * @param user The user address
     */
    function hasClaimedRent(uint256 propertyId, uint256 distributionIndex, address user) public view returns (bool) {
        require(distributionIndex < rentDistributions[propertyId].length, "Invalid distribution index");
        return rentDistributions[propertyId][distributionIndex].claimed[user];
    }

    /**
     * @dev Get unclaimed rent amount for a user
     * @param propertyId The ID of the property
     * @param user The user address
     */
    function getUnclaimedRent(uint256 propertyId, address user) public view returns (uint256) {
        Property storage property = properties[propertyId];
        uint256 userShares = property.shareholdings[user];
        
        if (userShares == 0) return 0;
        
        uint256 totalUnclaimed = 0;
        uint256 totalOwnedShares = property.totalShares - property.availableShares;
        
        for (uint256 i = 0; i < rentDistributions[propertyId].length; i++) {
            RentDistribution storage distribution = rentDistributions[propertyId][i];
            if (!distribution.claimed[user]) {
                uint256 rentAmount = (distribution.totalRent * userShares) / totalOwnedShares;
                totalUnclaimed += rentAmount;
            }
        }
        
        return totalUnclaimed;
    }

    /**
     * @dev Get property statistics
     * @param propertyId The ID of the property
     */
    function getPropertyStats(uint256 propertyId) public view returns (
        uint256 totalInvestors,
        uint256 totalRentDistributed,
        uint256 totalTransactions,
        uint256 occupancyRate
    ) {
        Property storage property = properties[propertyId];
        
        // Count unique investors (simplified - could be optimized)
        uint256 investorCount = 0;
        uint256 soldShares = property.totalShares - property.availableShares;
        
        uint256 totalRent = 0;
        for (uint256 i = 0; i < rentDistributions[propertyId].length; i++) {
            totalRent += rentDistributions[propertyId][i].totalRent;
        }
        
        uint256 occupancy = soldShares > 0 ? (soldShares * 100) / property.totalShares : 0;
        
        return (
            investorCount, // This would need a more sophisticated implementation
            totalRent,
            propertyPurchases[propertyId].length,
            occupancy
        );
    }
    
    // Override functions required for ERC721URIStorage
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }
    
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
