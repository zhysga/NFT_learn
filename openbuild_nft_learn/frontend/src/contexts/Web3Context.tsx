import React, { createContext, useContext, useEffect, useState, ReactNode } from 'react';
import { ethers } from 'ethers';
import detectEthereumProvider from '@metamask/detect-provider';
import toast from 'react-hot-toast';

// 类型定义
interface Web3ContextType {
  // 连接状态
  isConnected: boolean;
  isConnecting: boolean;
  account: string | null;
  chainId: number | null;
  balance: string;
  
  // Web3实例
  provider: ethers.providers.Web3Provider | null;
  signer: ethers.Signer | null;
  
  // 方法
  connectWallet: () => Promise<void>;
  disconnectWallet: () => void;
  switchNetwork: (chainId: number) => Promise<void>;
  
  // 合约实例
  nftContract: ethers.Contract | null;
  marketplaceContract: ethers.Contract | null;
}

// 支持的网络
export const SUPPORTED_NETWORKS = {
  1: {
    name: 'Ethereum Mainnet',
    rpcUrl: 'https://mainnet.infura.io/v3/YOUR_INFURA_KEY',
    blockExplorer: 'https://etherscan.io',
  },
  5: {
    name: 'Goerli Testnet',
    rpcUrl: 'https://goerli.infura.io/v3/YOUR_INFURA_KEY',
    blockExplorer: 'https://goerli.etherscan.io',
  },
  11155111: {
    name: 'Sepolia Testnet',
    rpcUrl: 'https://sepolia.infura.io/v3/YOUR_INFURA_KEY',
    blockExplorer: 'https://sepolia.etherscan.io',
  },
};

// 合约地址（需要根据部署后的实际地址更新）
const CONTRACT_ADDRESSES = {
  NFT: process.env.REACT_APP_NFT_CONTRACT_ADDRESS || '',
  MARKETPLACE: process.env.REACT_APP_MARKETPLACE_CONTRACT_ADDRESS || '',
};

// 合约ABI（简化版本，实际使用时需要完整ABI）
const NFT_ABI = [
  // 基本ERC721方法
  'function mintArtwork(address to, string memory uri, tuple(string name, string description, string aiModel, string prompt, string style, address creator, uint256 createdAt, uint256 votes, bool isVerified) metadata, address royaltyRecipient, uint96 royaltyFeeNumerator) public payable',
  'function batchMintArtworks(address to, string[] memory uris, tuple(string name, string description, string aiModel, string prompt, string style, address creator, uint256 createdAt, uint256 votes, bool isVerified)[] memory metadataArray, address royaltyRecipient, uint96 royaltyFeeNumerator) public payable',
  'function voteForArtwork(uint256 tokenId) public',
  'function getArtwork(uint256 tokenId) public view returns (tuple(string name, string description, string aiModel, string prompt, string style, address creator, uint256 createdAt, uint256 votes, bool isVerified))',
  'function getArtworksByCreator(address creator) public view returns (uint256[])',
  'function totalSupply() public view returns (uint256)',
  'function tokenURI(uint256 tokenId) public view returns (string)',
  'function ownerOf(uint256 tokenId) public view returns (address)',
  'function balanceOf(address owner) public view returns (uint256)',
  'function approve(address to, uint256 tokenId) public',
  'function setApprovalForAll(address operator, bool approved) public',
  'function isApprovedForAll(address owner, address operator) public view returns (bool)',
  'function mintPrice() public view returns (uint256)',
  'function maxSupply() public view returns (uint256)',
];

const MARKETPLACE_ABI = [
  'function listNFT(address nftContract, uint256 tokenId, uint256 price) public',
  'function buyNFT(uint256 listingId) public payable',
  'function cancelListing(uint256 listingId) public',
  'function createAuction(address nftContract, uint256 tokenId, uint256 startingPrice, uint256 duration) public',
  'function placeBid(uint256 auctionId) public payable',
  'function endAuction(uint256 auctionId) public',
  'function getActiveListings(uint256 offset, uint256 limit) public view returns (tuple(uint256 listingId, address nftContract, uint256 tokenId, address seller, uint256 price, bool active, uint256 createdAt)[])',
  'function getActiveAuctions(uint256 offset, uint256 limit) public view returns (tuple(uint256 auctionId, address nftContract, uint256 tokenId, address seller, uint256 startingPrice, uint256 currentBid, address currentBidder, uint256 endTime, bool active, uint256 createdAt)[])',
  'function marketplaceFeeRate() public view returns (uint256)',
];

// 创建上下文
const Web3Context = createContext<Web3ContextType | undefined>(undefined);

// 提供者组件
export const Web3Provider: React.FC<{ children: ReactNode }> = ({ children }) => {
  const [isConnected, setIsConnected] = useState(false);
  const [isConnecting, setIsConnecting] = useState(false);
  const [account, setAccount] = useState<string | null>(null);
  const [chainId, setChainId] = useState<number | null>(null);
  const [balance, setBalance] = useState('0');
  const [provider, setProvider] = useState<ethers.providers.Web3Provider | null>(null);
  const [signer, setSigner] = useState<ethers.Signer | null>(null);
  const [nftContract, setNftContract] = useState<ethers.Contract | null>(null);
  const [marketplaceContract, setMarketplaceContract] = useState<ethers.Contract | null>(null);

  // 初始化Web3连接
  const initializeWeb3 = async (ethereumProvider: any) => {
    try {
      const web3Provider = new ethers.providers.Web3Provider(ethereumProvider);
      const web3Signer = web3Provider.getSigner();
      const accounts = await web3Provider.listAccounts();
      const network = await web3Provider.getNetwork();
      
      if (accounts.length > 0) {
        const userBalance = await web3Provider.getBalance(accounts[0]);
        
        setProvider(web3Provider);
        setSigner(web3Signer);
        setAccount(accounts[0]);
        setChainId(network.chainId);
        setBalance(ethers.utils.formatEther(userBalance));
        setIsConnected(true);

        // 初始化合约实例
        if (CONTRACT_ADDRESSES.NFT) {
          const nft = new ethers.Contract(CONTRACT_ADDRESSES.NFT, NFT_ABI, web3Signer);
          setNftContract(nft);
        }

        if (CONTRACT_ADDRESSES.MARKETPLACE) {
          const marketplace = new ethers.Contract(CONTRACT_ADDRESSES.MARKETPLACE, MARKETPLACE_ABI, web3Signer);
          setMarketplaceContract(marketplace);
        }
      }
    } catch (error) {
      console.error('初始化Web3失败:', error);
      toast.error('初始化Web3失败');
    }
  };

  // 连接钱包
  const connectWallet = async () => {
    if (isConnecting) return;
    
    setIsConnecting(true);
    
    try {
      const ethereumProvider = await detectEthereumProvider();
      
      if (!ethereumProvider) {
        toast.error('请安装MetaMask钱包');
        return;
      }

      // 请求连接账户
      await ethereumProvider.request({
        method: 'eth_requestAccounts',
      });

      await initializeWeb3(ethereumProvider);
      toast.success('钱包连接成功');
      
    } catch (error: any) {
      console.error('连接钱包失败:', error);
      
      if (error.code === 4001) {
        toast.error('用户拒绝连接钱包');
      } else {
        toast.error('连接钱包失败');
      }
    } finally {
      setIsConnecting(false);
    }
  };

  // 断开钱包连接
  const disconnectWallet = () => {
    setIsConnected(false);
    setAccount(null);
    setChainId(null);
    setBalance('0');
    setProvider(null);
    setSigner(null);
    setNftContract(null);
    setMarketplaceContract(null);
    toast.success('钱包已断开连接');
  };

  // 切换网络
  const switchNetwork = async (targetChainId: number) => {
    if (!provider) return;

    try {
      await provider.send('wallet_switchEthereumChain', [
        { chainId: ethers.utils.hexValue(targetChainId) },
      ]);
    } catch (error: any) {
      // 如果网络不存在，尝试添加网络
      if (error.code === 4902) {
        const networkConfig = SUPPORTED_NETWORKS[targetChainId as keyof typeof SUPPORTED_NETWORKS];
        if (networkConfig) {
          try {
            await provider.send('wallet_addEthereumChain', [
              {
                chainId: ethers.utils.hexValue(targetChainId),
                chainName: networkConfig.name,
                rpcUrls: [networkConfig.rpcUrl],
                blockExplorerUrls: [networkConfig.blockExplorer],
              },
            ]);
          } catch (addError) {
            console.error('添加网络失败:', addError);
            toast.error('添加网络失败');
          }
        }
      } else {
        console.error('切换网络失败:', error);
        toast.error('切换网络失败');
      }
    }
  };

  // 监听账户和网络变化
  useEffect(() => {
    const handleAccountsChanged = (accounts: string[]) => {
      if (accounts.length === 0) {
        disconnectWallet();
      } else if (accounts[0] !== account) {
        setAccount(accounts[0]);
        // 重新获取余额
        if (provider) {
          provider.getBalance(accounts[0]).then((balance) => {
            setBalance(ethers.utils.formatEther(balance));
          });
        }
      }
    };

    const handleChainChanged = (chainId: string) => {
      const newChainId = parseInt(chainId, 16);
      setChainId(newChainId);
      
      // 检查是否为支持的网络
      if (!SUPPORTED_NETWORKS[newChainId as keyof typeof SUPPORTED_NETWORKS]) {
        toast.error('不支持的网络，请切换到支持的网络');
      }
    };

    // 检查是否已连接
    const checkConnection = async () => {
      const ethereumProvider = await detectEthereumProvider();
      if (ethereumProvider && ethereumProvider.isConnected()) {
        const accounts = await ethereumProvider.request({ method: 'eth_accounts' });
        if (accounts.length > 0) {
          await initializeWeb3(ethereumProvider);
        }
      }
    };

    checkConnection();

    // 添加事件监听器
    if (window.ethereum) {
      window.ethereum.on('accountsChanged', handleAccountsChanged);
      window.ethereum.on('chainChanged', handleChainChanged);
    }

    // 清理事件监听器
    return () => {
      if (window.ethereum) {
        window.ethereum.removeListener('accountsChanged', handleAccountsChanged);
        window.ethereum.removeListener('chainChanged', handleChainChanged);
      }
    };
  }, [account, provider]);

  const contextValue: Web3ContextType = {
    isConnected,
    isConnecting,
    account,
    chainId,
    balance,
    provider,
    signer,
    connectWallet,
    disconnectWallet,
    switchNetwork,
    nftContract,
    marketplaceContract,
  };

  return (
    <Web3Context.Provider value={contextValue}>
      {children}
    </Web3Context.Provider>
  );
};

// Hook for using Web3 context
export const useWeb3 = (): Web3ContextType => {
  const context = useContext(Web3Context);
  if (context === undefined) {
    throw new Error('useWeb3 must be used within a Web3Provider');
  }
  return context;
};

// 声明全局window.ethereum类型
declare global {
  interface Window {
    ethereum?: any;
  }
} 