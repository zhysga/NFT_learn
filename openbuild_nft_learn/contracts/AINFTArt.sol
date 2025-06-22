// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title AINFTArt
 * @dev AI生成的NFT艺术品智能合约
 * 支持自动版税分配、批量铸造、社区投票等功能
 */
contract AINFTArt is ERC721, ERC721URIStorage, ERC721Royalty, Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    
    // 代币ID计数器
    Counters.Counter private _tokenIdCounter;
    
    // 铸造费用
    uint256 public mintPrice = 0.01 ether;
    
    // 平台手续费比例 (基点，10000 = 100%)
    uint256 public platformFeeRate = 250; // 2.5%
    
    // 最大供应量
    uint256 public maxSupply = 10000;
    
    // 每个地址最大铸造数量
    uint256 public maxMintPerAddress = 10;
    
    // 艺术品元数据结构
    struct ArtworkMetadata {
        string name;
        string description;
        string aiModel;
        string prompt;
        string style;
        address creator;
        uint256 createdAt;
        uint256 votes;
        bool isVerified;
    }
    
    // 代币ID到艺术品元数据的映射
    mapping(uint256 => ArtworkMetadata) public artworks;
    
    // 地址到铸造数量的映射
    mapping(address => uint256) public mintedCount;
    
    // 社区投票映射
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    
    // 验证艺术家列表
    mapping(address => bool) public verifiedArtists;
    
    // 事件定义
    event ArtworkMinted(
        uint256 indexed tokenId,
        address indexed creator,
        string name,
        string aiModel,
        string style
    );
    
    event ArtworkVoted(
        uint256 indexed tokenId,
        address indexed voter,
        uint256 totalVotes
    );
    
    event ArtistVerified(address indexed artist);
    
    event RoyaltyUpdated(
        uint256 indexed tokenId,
        address indexed recipient,
        uint96 feeNumerator
    );

    constructor() ERC721("AI NFT Art", "AINFT") {}

    /**
     * @dev 铸造新的AI艺术品NFT
     * @param to 接收者地址
     * @param uri 元数据URI
     * @param metadata 艺术品元数据
     * @param royaltyRecipient 版税接收者
     * @param royaltyFeeNumerator 版税比例（基点）
     */
    function mintArtwork(
        address to,
        string memory uri,
        ArtworkMetadata memory metadata,
        address royaltyRecipient,
        uint96 royaltyFeeNumerator
    ) public payable nonReentrant {
        require(msg.value >= mintPrice, "Insufficient payment");
        require(_tokenIdCounter.current() < maxSupply, "Max supply reached");
        require(mintedCount[msg.sender] < maxMintPerAddress, "Max mint per address exceeded");
        require(bytes(metadata.name).length > 0, "Name cannot be empty");
        require(bytes(metadata.prompt).length > 0, "Prompt cannot be empty");
        
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        
        // 铸造NFT
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        
        // 设置版税
        _setTokenRoyalty(tokenId, royaltyRecipient, royaltyFeeNumerator);
        
        // 存储艺术品元数据
        metadata.creator = msg.sender;
        metadata.createdAt = block.timestamp;
        metadata.votes = 0;
        metadata.isVerified = verifiedArtists[msg.sender];
        artworks[tokenId] = metadata;
        
        // 更新铸造计数
        mintedCount[msg.sender]++;
        
        // 分配铸造费用
        _distributeMintFee();
        
        emit ArtworkMinted(tokenId, msg.sender, metadata.name, metadata.aiModel, metadata.style);
    }

    /**
     * @dev 批量铸造AI艺术品
     * @param to 接收者地址
     * @param uris 元数据URI数组
     * @param metadataArray 艺术品元数据数组
     * @param royaltyRecipient 版税接收者
     * @param royaltyFeeNumerator 版税比例
     */
    function batchMintArtworks(
        address to,
        string[] memory uris,
        ArtworkMetadata[] memory metadataArray,
        address royaltyRecipient,
        uint96 royaltyFeeNumerator
    ) public payable nonReentrant {
        require(uris.length == metadataArray.length, "Arrays length mismatch");
        require(uris.length > 0, "Empty arrays");
        require(msg.value >= mintPrice * uris.length, "Insufficient payment");
        require(_tokenIdCounter.current() + uris.length <= maxSupply, "Max supply exceeded");
        require(mintedCount[msg.sender] + uris.length <= maxMintPerAddress, "Max mint exceeded");
        
        for (uint256 i = 0; i < uris.length; i++) {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            
            _safeMint(to, tokenId);
            _setTokenURI(tokenId, uris[i]);
            _setTokenRoyalty(tokenId, royaltyRecipient, royaltyFeeNumerator);
            
            ArtworkMetadata memory metadata = metadataArray[i];
            metadata.creator = msg.sender;
            metadata.createdAt = block.timestamp;
            metadata.votes = 0;
            metadata.isVerified = verifiedArtists[msg.sender];
            artworks[tokenId] = metadata;
            
            emit ArtworkMinted(tokenId, msg.sender, metadata.name, metadata.aiModel, metadata.style);
        }
        
        mintedCount[msg.sender] += uris.length;
        _distributeMintFee();
    }

    /**
     * @dev 社区投票功能
     * @param tokenId 代币ID
     */
    function voteForArtwork(uint256 tokenId) public {
        require(_exists(tokenId), "Token does not exist");
        require(!hasVoted[tokenId][msg.sender], "Already voted");
        require(ownerOf(tokenId) != msg.sender, "Cannot vote for own artwork");
        
        hasVoted[tokenId][msg.sender] = true;
        artworks[tokenId].votes++;
        
        emit ArtworkVoted(tokenId, msg.sender, artworks[tokenId].votes);
    }

    /**
     * @dev 获取艺术品详细信息
     * @param tokenId 代币ID
     * @return 艺术品元数据
     */
    function getArtwork(uint256 tokenId) public view returns (ArtworkMetadata memory) {
        require(_exists(tokenId), "Token does not exist");
        return artworks[tokenId];
    }

    /**
     * @dev 获取用户创作的所有艺术品
     * @param creator 创作者地址
     * @return tokenIds 代币ID数组
     */
    function getArtworksByCreator(address creator) public view returns (uint256[] memory) {
        uint256 totalTokens = _tokenIdCounter.current();
        uint256 count = 0;
        
        // 计算该创作者的作品数量
        for (uint256 i = 0; i < totalTokens; i++) {
            if (artworks[i].creator == creator) {
                count++;
            }
        }
        
        // 创建结果数组
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        
        for (uint256 i = 0; i < totalTokens; i++) {
            if (artworks[i].creator == creator) {
                result[index] = i;
                index++;
            }
        }
        
        return result;
    }

    /**
     * @dev 获取最受欢迎的艺术品（按投票数排序）
     * @param limit 返回数量限制
     * @return tokenIds 代币ID数组
     */
    function getTopArtworks(uint256 limit) public view returns (uint256[] memory) {
        uint256 totalTokens = _tokenIdCounter.current();
        require(totalTokens > 0, "No artworks exist");
        
        if (limit > totalTokens) {
            limit = totalTokens;
        }
        
        // 简化版本：返回前N个代币ID（实际应用中需要更复杂的排序逻辑）
        uint256[] memory result = new uint256[](limit);
        for (uint256 i = 0; i < limit; i++) {
            result[i] = i;
        }
        
        return result;
    }

    /**
     * @dev 验证艺术家身份
     * @param artist 艺术家地址
     */
    function verifyArtist(address artist) public onlyOwner {
        verifiedArtists[artist] = true;
        emit ArtistVerified(artist);
    }

    /**
     * @dev 取消艺术家验证
     * @param artist 艺术家地址
     */
    function revokeArtistVerification(address artist) public onlyOwner {
        verifiedArtists[artist] = false;
    }

    /**
     * @dev 更新铸造价格
     * @param newPrice 新价格
     */
    function updateMintPrice(uint256 newPrice) public onlyOwner {
        mintPrice = newPrice;
    }

    /**
     * @dev 更新平台手续费率
     * @param newRate 新费率（基点）
     */
    function updatePlatformFeeRate(uint256 newRate) public onlyOwner {
        require(newRate <= 1000, "Fee rate too high"); // 最大10%
        platformFeeRate = newRate;
    }

    /**
     * @dev 更新特定NFT的版税信息
     * @param tokenId 代币ID
     * @param recipient 版税接收者
     * @param feeNumerator 版税比例
     */
    function updateTokenRoyalty(
        uint256 tokenId,
        address recipient,
        uint96 feeNumerator
    ) public {
        require(_exists(tokenId), "Token does not exist");
        require(
            msg.sender == artworks[tokenId].creator || msg.sender == owner(),
            "Not authorized"
        );
        
        _setTokenRoyalty(tokenId, recipient, feeNumerator);
        emit RoyaltyUpdated(tokenId, recipient, feeNumerator);
    }

    /**
     * @dev 分配铸造费用
     */
    function _distributeMintFee() private {
        uint256 totalFee = msg.value;
        uint256 platformFee = (totalFee * platformFeeRate) / 10000;
        uint256 creatorFee = totalFee - platformFee;
        
        // 转账给平台
        if (platformFee > 0) {
            payable(owner()).transfer(platformFee);
        }
        
        // 剩余费用可以用于其他用途（如社区奖励池）
        // 这里简化处理，实际应用中可以有更复杂的分配逻辑
    }

    /**
     * @dev 提取合约余额
     */
    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");
        payable(owner()).transfer(balance);
    }

    /**
     * @dev 获取当前代币供应量
     */
    function totalSupply() public view returns (uint256) {
        return _tokenIdCounter.current();
    }

    /**
     * @dev 检查代币是否存在
     */
    function exists(uint256 tokenId) public view returns (bool) {
        return _exists(tokenId);
    }

    // 重写必要的函数以支持多重继承
    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage, ERC721Royalty) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Royalty)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
} 