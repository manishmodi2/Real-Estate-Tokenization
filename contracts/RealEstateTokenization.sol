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
        mapping(address => uint256) shareholdings;
    }
    
    struct SharePurchase {
        uint256 propertyId;
        address buyer;
        uint256 shares;
        uint256 totalCost;
        uint256 timestamp;
    }
    
    mapping(uint256 => Property) public properties;
    mapping(uint256 => SharePurchase[]) public propertyPurchases;
    mapping(address => uint256[]) public userProperties;
    
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
    
    constructor() ERC721("RealEstateTokens", "RET") Ownable(msg.sender) {}
    
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
        require(shares > 0, "Shares must be greater than 0");
        require(shares <= property.availableShares, "Not enough shares available");
        
        uint256 totalCost = shares * property.pricePerShare;
        require(msg.value >= totalCost, "Insufficient payment");
        
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
        
        // Transfer payment to property owner
        payable(property.propertyOwner).transfer(totalCost);
        
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
    
    // View functions
    function getPropertyDetails(uint256 propertyId) public view returns (
        string memory propertyAddress,
        uint256 totalValue,
        uint256 totalShares,
        uint256 availableShares,
        uint256 pricePerShare,
        address propertyOwner,
        bool isActive
    ) {
        Property storage property = properties[propertyId];
        return (
            property.propertyAddress,
            property.totalValue,
            property.totalShares,
            property.availableShares,
            property.pricePerShare,
            property.propertyOwner,
            property.isActive
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
    
    // Override functions required for ERC721URIStorage
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }
    
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
