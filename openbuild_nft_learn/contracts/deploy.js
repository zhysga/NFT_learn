const { ethers } = require("hardhat");

async function main() {
    console.log("开始部署AI NFT艺术平台智能合约...");
    
    // 获取部署者账户
    const [deployer] = await ethers.getSigners();
    console.log("部署账户:", deployer.address);
    console.log("账户余额:", (await deployer.getBalance()).toString());

    // 部署主NFT合约
    console.log("\n部署AINFTArt合约...");
    const AINFTArt = await ethers.getContractFactory("AINFTArt");
    const aiNFTArt = await AINFTArt.deploy();
    await aiNFTArt.deployed();
    console.log("AINFTArt合约地址:", aiNFTArt.address);

    // 部署市场合约
    console.log("\n部署AINFTMarketplace合约...");
    const AINFTMarketplace = await ethers.getContractFactory("AINFTMarketplace");
    const marketplace = await AINFTMarketplace.deploy();
    await marketplace.deployed();
    console.log("AINFTMarketplace合约地址:", marketplace.address);

    // 验证合约部署
    console.log("\n验证合约部署状态...");
    const nftName = await aiNFTArt.name();
    const nftSymbol = await aiNFTArt.symbol();
    const mintPrice = await aiNFTArt.mintPrice();
    const maxSupply = await aiNFTArt.maxSupply();
    
    console.log("NFT名称:", nftName);
    console.log("NFT符号:", nftSymbol);
    console.log("铸造价格:", ethers.utils.formatEther(mintPrice), "ETH");
    console.log("最大供应量:", maxSupply.toString());

    const marketplaceFeeRate = await marketplace.marketplaceFeeRate();
    console.log("市场手续费率:", (marketplaceFeeRate.toNumber() / 100).toString() + "%");

    // 保存合约地址到配置文件
    const fs = require('fs');
    const contractAddresses = {
        AINFTArt: aiNFTArt.address,
        AINFTMarketplace: marketplace.address,
        network: network.name,
        deployer: deployer.address
    };
    
    fs.writeFileSync(
        './contract-addresses.json',
        JSON.stringify(contractAddresses, null, 2)
    );
    
    console.log("\n合约地址已保存到 contract-addresses.json");
    console.log("✅ 所有合约部署完成!");
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error("部署失败:", error);
        process.exit(1);
    }); 