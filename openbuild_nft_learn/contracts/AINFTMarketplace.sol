// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title AINFTMarketplace
 * @dev AI NFT艺术品市场合约
 * 支持固定价格销售、拍卖、版税自动分配等功能
 */
contract AINFTMarketplace is ReentrancyGuard, Ownable, IERC721Receiver {
    using Counters for Counters.Counter;
    
    // 市场手续费率（基点，10000 = 100%）
    uint256 public marketplaceFeeRate = 250; // 2.5%
    
    // 拍卖ID计数器
    Counters.Counter private _auctionIdCounter;
    
    // 销售列表ID计数器
    Counters.Counter private _listingIdCounter;
    
    // 销售列表结构
    struct Listing {
        uint256 listingId;
        address nftContract;
        uint256 tokenId;
        address seller;
        uint256 price;
        bool active;
        uint256 createdAt;
    }
    
    // 拍卖结构
    struct Auction {
        uint256 auctionId;
        address nftContract;
        uint256 tokenId;
        address seller;
        uint256 startingPrice;
        uint256 currentBid;
        address currentBidder;
        uint256 endTime;
        bool active;
        uint256 createdAt;
    }
    
    // 出价结构
    struct Bid {
        address bidder;
        uint256 amount;
        uint256 timestamp;
    }
    
    // 映射
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => Bid[]) public auctionBids;
    mapping(address => mapping(uint256 => uint256)) public nftToListing;
    mapping(address => mapping(uint256 => uint256)) public nftToAuction;
    
    // 事件
    event NFTListed(
        uint256 indexed listingId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        uint256 price
    );
    
    event NFTSold(
        uint256 indexed listingId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        address buyer,
        uint256 price
    );
    
    event ListingCancelled(
        uint256 indexed listingId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller
    );
    
    event AuctionCreated(
        uint256 indexed auctionId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        uint256 startingPrice,
        uint256 endTime
    );
    
    event BidPlaced(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 amount
    );
    
    event AuctionEnded(
        uint256 indexed auctionId,
        address indexed winner,
        uint256 winningBid
    );
    
    event AuctionCancelled(
        uint256 indexed auctionId,
        address indexed seller
    );

    constructor() {}

    /**
     * @dev 列出NFT进行销售
     */
    function listNFT(
        address nftContract,
        uint256 tokenId,
        uint256 price
    ) public nonReentrant {
        require(price > 0, "Price must be greater than 0");
        require(
            IERC721(nftContract).ownerOf(tokenId) == msg.sender,
            "Not the owner of this NFT"
        );
        
        _listingIdCounter.increment();
        uint256 listingId = _listingIdCounter.current();
        
        listings[listingId] = Listing({
            listingId: listingId,
            nftContract: nftContract,
            tokenId: tokenId,
            seller: msg.sender,
            price: price,
            active: true,
            createdAt: block.timestamp
        });
        
        nftToListing[nftContract][tokenId] = listingId;
        
        emit NFTListed(listingId, nftContract, tokenId, msg.sender, price);
    }

    /**
     * @dev 购买NFT
     */
    function buyNFT(uint256 listingId) public payable nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(msg.value >= listing.price, "Insufficient payment");
        require(msg.sender != listing.seller, "Cannot buy your own NFT");
        
        listing.active = false;
        nftToListing[listing.nftContract][listing.tokenId] = 0;
        
        // 计算费用分配
        uint256 totalPrice = listing.price;
        uint256 marketplaceFee = (totalPrice * marketplaceFeeRate) / 10000;
        uint256 sellerAmount = totalPrice - marketplaceFee;
        
        // 转移NFT
        IERC721(listing.nftContract).safeTransferFrom(
            listing.seller,
            msg.sender,
            listing.tokenId
        );
        
        // 分配资金
        if (marketplaceFee > 0) {
            payable(owner()).transfer(marketplaceFee);
        }
        
        payable(listing.seller).transfer(sellerAmount);
        
        // 退还多余的支付
        if (msg.value > listing.price) {
            payable(msg.sender).transfer(msg.value - listing.price);
        }
        
        emit NFTSold(
            listingId,
            listing.nftContract,
            listing.tokenId,
            listing.seller,
            msg.sender,
            listing.price
        );
    }

    /**
     * @dev 取消NFT销售
     * @param listingId 销售列表ID
     */
    function cancelListing(uint256 listingId) public nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(
            msg.sender == listing.seller || msg.sender == owner(),
            "Not authorized"
        );
        
        listing.active = false;
        nftToListing[listing.nftContract][listing.tokenId] = 0;
        
        emit ListingCancelled(
            listingId,
            listing.nftContract,
            listing.tokenId,
            listing.seller
        );
    }

    /**
     * @dev 创建拍卖
     * @param nftContract NFT合约地址
     * @param tokenId 代币ID
     * @param startingPrice 起始价格
     * @param duration 拍卖持续时间（秒）
     */
    function createAuction(
        address nftContract,
        uint256 tokenId,
        uint256 startingPrice,
        uint256 duration
    ) public nonReentrant {
        require(startingPrice > 0, "Starting price must be greater than 0");
        require(duration >= 3600, "Duration must be at least 1 hour");
        require(duration <= 7 days, "Duration cannot exceed 7 days");
        require(
            IERC721(nftContract).ownerOf(tokenId) == msg.sender,
            "Not the owner of this NFT"
        );
        require(
            IERC721(nftContract).isApprovedForAll(msg.sender, address(this)) ||
            IERC721(nftContract).getApproved(tokenId) == address(this),
            "Marketplace not approved"
        );
        require(
            nftToListing[nftContract][tokenId] == 0,
            "NFT is listed for sale"
        );
        require(
            nftToAuction[nftContract][tokenId] == 0,
            "NFT already in auction"
        );
        
        _auctionIdCounter.increment();
        uint256 auctionId = _auctionIdCounter.current();
        
        auctions[auctionId] = Auction({
            auctionId: auctionId,
            nftContract: nftContract,
            tokenId: tokenId,
            seller: msg.sender,
            startingPrice: startingPrice,
            currentBid: 0,
            currentBidder: address(0),
            endTime: block.timestamp + duration,
            active: true,
            createdAt: block.timestamp
        });
        
        nftToAuction[nftContract][tokenId] = auctionId;
        
        // 将NFT转移到合约
        IERC721(nftContract).safeTransferFrom(msg.sender, address(this), tokenId);
        
        emit AuctionCreated(
            auctionId,
            nftContract,
            tokenId,
            msg.sender,
            startingPrice,
            block.timestamp + duration
        );
    }

    /**
     * @dev 参与拍卖出价
     * @param auctionId 拍卖ID
     */
    function placeBid(uint256 auctionId) public payable nonReentrant {
        Auction storage auction = auctions[auctionId];
        require(auction.active, "Auction not active");
        require(block.timestamp < auction.endTime, "Auction has ended");
        require(msg.sender != auction.seller, "Cannot bid on your own auction");
        
        uint256 minBid = auction.currentBid > 0 
            ? auction.currentBid + (auction.currentBid * 5 / 100) // 最少增加5%
            : auction.startingPrice;
            
        require(msg.value >= minBid, "Bid too low");
        
        // 退还前一个出价者的资金
        if (auction.currentBidder != address(0)) {
            payable(auction.currentBidder).transfer(auction.currentBid);
        }
        
        // 更新拍卖信息
        auction.currentBid = msg.value;
        auction.currentBidder = msg.sender;
        
        // 记录出价历史
        auctionBids[auctionId].push(Bid({
            bidder: msg.sender,
            amount: msg.value,
            timestamp: block.timestamp
        }));
        
        emit BidPlaced(auctionId, msg.sender, msg.value);
    }

    /**
     * @dev 结束拍卖
     * @param auctionId 拍卖ID
     */
    function endAuction(uint256 auctionId) public nonReentrant {
        Auction storage auction = auctions[auctionId];
        require(auction.active, "Auction not active");
        require(
            block.timestamp >= auction.endTime ||
            msg.sender == auction.seller ||
            msg.sender == owner(),
            "Auction not ended yet"
        );
        
        auction.active = false;
        nftToAuction[auction.nftContract][auction.tokenId] = 0;
        
        if (auction.currentBidder != address(0)) {
            // 有出价者，完成交易
            uint256 totalPrice = auction.currentBid;
            uint256 marketplaceFee = (totalPrice * marketplaceFeeRate) / 10000;
            uint256 royaltyAmount = 0;
            address royaltyRecipient = address(0);
            
            // 检查版税
            if (IERC165(auction.nftContract).supportsInterface(type(IERC2981).interfaceId)) {
                (royaltyRecipient, royaltyAmount) = IERC2981(auction.nftContract)
                    .royaltyInfo(auction.tokenId, totalPrice);
            }
            
            uint256 sellerAmount = totalPrice - marketplaceFee - royaltyAmount;
            
            // 转移NFT给获胜者
            IERC721(auction.nftContract).safeTransferFrom(
                address(this),
                auction.currentBidder,
                auction.tokenId
            );
            
            // 分配资金
            if (marketplaceFee > 0) {
                payable(owner()).transfer(marketplaceFee);
            }
            
            if (royaltyAmount > 0 && royaltyRecipient != address(0)) {
                payable(royaltyRecipient).transfer(royaltyAmount);
            }
            
            payable(auction.seller).transfer(sellerAmount);
            
            emit AuctionEnded(auctionId, auction.currentBidder, auction.currentBid);
        } else {
            // 无出价者，将NFT退还给卖家
            IERC721(auction.nftContract).safeTransferFrom(
                address(this),
                auction.seller,
                auction.tokenId
            );
            
            emit AuctionCancelled(auctionId, auction.seller);
        }
    }

    /**
     * @dev 取消拍卖（仅限无出价时）
     * @param auctionId 拍卖ID
     */
    function cancelAuction(uint256 auctionId) public nonReentrant {
        Auction storage auction = auctions[auctionId];
        require(auction.active, "Auction not active");
        require(
            msg.sender == auction.seller || msg.sender == owner(),
            "Not authorized"
        );
        require(auction.currentBidder == address(0), "Cannot cancel auction with bids");
        
        auction.active = false;
        nftToAuction[auction.nftContract][auction.tokenId] = 0;
        
        // 将NFT退还给卖家
        IERC721(auction.nftContract).safeTransferFrom(
            address(this),
            auction.seller,
            auction.tokenId
        );
        
        emit AuctionCancelled(auctionId, auction.seller);
    }

    /**
     * @dev 获取拍卖出价历史
     * @param auctionId 拍卖ID
     * @return 出价历史数组
     */
    function getAuctionBids(uint256 auctionId) public view returns (Bid[] memory) {
        return auctionBids[auctionId];
    }

    /**
     * @dev 获取活跃的销售列表
     * @param offset 偏移量
     * @param limit 限制数量
     * @return 销售列表数组
     */
    function getActiveListings(uint256 offset, uint256 limit) 
        public view returns (Listing[] memory) {
        uint256 totalListings = _listingIdCounter.current();
        require(offset < totalListings, "Offset out of bounds");
        
        uint256 end = offset + limit;
        if (end > totalListings) {
            end = totalListings;
        }
        
        uint256 activeCount = 0;
        for (uint256 i = offset + 1; i <= end; i++) {
            if (listings[i].active) {
                activeCount++;
            }
        }
        
        Listing[] memory result = new Listing[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = offset + 1; i <= end && index < activeCount; i++) {
            if (listings[i].active) {
                result[index] = listings[i];
                index++;
            }
        }
        
        return result;
    }

    /**
     * @dev 获取活跃的拍卖
     * @param offset 偏移量
     * @param limit 限制数量
     * @return 拍卖数组
     */
    function getActiveAuctions(uint256 offset, uint256 limit) 
        public view returns (Auction[] memory) {
        uint256 totalAuctions = _auctionIdCounter.current();
        require(offset < totalAuctions, "Offset out of bounds");
        
        uint256 end = offset + limit;
        if (end > totalAuctions) {
            end = totalAuctions;
        }
        
        uint256 activeCount = 0;
        for (uint256 i = offset + 1; i <= end; i++) {
            if (auctions[i].active && block.timestamp < auctions[i].endTime) {
                activeCount++;
            }
        }
        
        Auction[] memory result = new Auction[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = offset + 1; i <= end && index < activeCount; i++) {
            if (auctions[i].active && block.timestamp < auctions[i].endTime) {
                result[index] = auctions[i];
                index++;
            }
        }
        
        return result;
    }

    /**
     * @dev 更新市场手续费率
     * @param newRate 新费率（基点）
     */
    function updateMarketplaceFeeRate(uint256 newRate) public onlyOwner {
        require(newRate <= 1000, "Fee rate too high"); // 最大10%
        marketplaceFeeRate = newRate;
    }

    /**
     * @dev 紧急提取合约中的ETH
     */
    function emergencyWithdraw() public onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    /**
     * @dev 获取总销售列表数量
     */
    function getTotalListings() public view returns (uint256) {
        return _listingIdCounter.current();
    }

    /**
     * @dev 获取总拍卖数量
     */
    function getTotalAuctions() public view returns (uint256) {
        return _auctionIdCounter.current();
    }

    /**
     * @dev 实现IERC721Receiver接口
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
} 