const hre = require("hardhat");
const { ethers } = require("hardhat");

async function main() {
  console.log("🚀 Deploying KipuBankV2...\n");

  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", ethers.formatEther(await ethers.provider.getBalance(deployer.address)), "ETH\n");

  // Network-specific configurations
  const network = hre.network.name;
  let ethUsdPriceFeed;
  let deployMockOracle = false;

  // Chainlink Price Feed addresses
  const priceFeeds = {
    mainnet: "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419", // ETH/USD Mainnet
    sepolia: "0x694AA1769357215DE4FAC081bf1f309aDC325306", // ETH/USD Sepolia
    goerli: "0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e",  // ETH/USD Goerli
  };

  // Deployment parameters
  const bankCapUSD = ethers.parseUnits("1000000", 6);      // $1,000,000 USD
  const withdrawalLimitUSD = ethers.parseUnits("10000", 6); // $10,000 USD

  console.log("📋 Deployment Configuration:");
  console.log("Network:", network);
  console.log("Bank Cap:", ethers.formatUnits(bankCapUSD, 6), "USD");
  console.log("Withdrawal Limit:", ethers.formatUnits(withdrawalLimitUSD, 6), "USD\n");

  // Determine price feed address
  if (network === "hardhat" || network === "localhost") {
    console.log("⚠️  Local network detected - deploying MockV3Aggregator...");
    deployMockOracle = true;

    // Deploy mock price feed with initial price of $2000 USD per ETH
    const MockV3Aggregator = await ethers.getContractFactory("MockV3Aggregator");
    const mockPriceFeed = await MockV3Aggregator.deploy(
      8, // decimals
      200000000000 // $2000 USD with 8 decimals
    );
    await mockPriceFeed.waitForDeployment();
    ethUsdPriceFeed = await mockPriceFeed.getAddress();
    console.log("✅ MockV3Aggregator deployed to:", ethUsdPriceFeed);
    console.log("   Initial ETH/USD price: $2000.00\n");
  } else if (priceFeeds[network]) {
    ethUsdPriceFeed = priceFeeds[network];
    console.log("✅ Using Chainlink ETH/USD price feed:", ethUsdPriceFeed, "\n");
  } else {
    throw new Error(`No price feed configured for network: ${network}`);
  }

  // Deploy KipuBankV2
  console.log("📝 Deploying KipuBankV2 contract...");
  const KipuBankV2 = await ethers.getContractFactory("KipuBankV2");
  const kipuBank = await KipuBankV2.deploy(
    ethUsdPriceFeed,
    bankCapUSD,
    withdrawalLimitUSD
  );

  await kipuBank.waitForDeployment();
  const kipuBankAddress = await kipuBank.getAddress();

  console.log("✅ KipuBankV2 deployed to:", kipuBankAddress);
  console.log("\n" + "=".repeat(60));
  console.log("🎉 DEPLOYMENT SUCCESSFUL!");
  console.log("=".repeat(60));

  // Display deployment summary
  console.log("\n📊 Deployment Summary:");
  console.log("├─ Contract: KipuBankV2");
  console.log("├─ Address:", kipuBankAddress);
  console.log("├─ Network:", network);
  console.log("├─ Price Feed:", ethUsdPriceFeed);
  console.log("├─ Bank Cap:", ethers.formatUnits(bankCapUSD, 6), "USD");
  console.log("└─ Withdrawal Limit:", ethers.formatUnits(withdrawalLimitUSD, 6), "USD");

  // Get current ETH price
  try {
    const ethPrice = await kipuBank.getETHPriceUSD();
    console.log("\n💰 Current ETH/USD Price:", ethers.formatUnits(ethPrice, 8), "USD");
  } catch (error) {
    console.log("\n⚠️  Could not fetch ETH price");
  }

  // Verification instructions
  if (network !== "hardhat" && network !== "localhost") {
    console.log("\n🔍 To verify on Etherscan, run:");
    console.log(`npx hardhat verify --network ${network} ${kipuBankAddress} "${ethUsdPriceFeed}" "${bankCapUSD}" "${withdrawalLimitUSD}"`);
  }

  // Save deployment info
  const deploymentInfo = {
    network,
    timestamp: new Date().toISOString(),
    deployer: deployer.address,
    contracts: {
      KipuBankV2: kipuBankAddress,
      PriceFeed: ethUsdPriceFeed,
    },
    parameters: {
      bankCapUSD: bankCapUSD.toString(),
      withdrawalLimitUSD: withdrawalLimitUSD.toString(),
    },
  };

  console.log("\n💾 Deployment Info:");
  console.log(JSON.stringify(deploymentInfo, null, 2));

  console.log("\n✨ Deployment complete!\n");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ Deployment failed:");
    console.error(error);
    process.exit(1);
  });
