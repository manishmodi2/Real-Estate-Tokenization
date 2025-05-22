const hre = require("hardhat");

async function main() {
  console.log("🚀 Starting Real Estate Tokenization Contract Deployment...");
  
  // Get the contract factory
  const Project = await hre.ethers.getContractFactory("Project");
  
  console.log("📋 Deploying contract...");
  
  // Deploy the contract
  const project = await Project.deploy();
  
  // Wait for the contract to be deployed
  await project.waitForDeployment();
  
  const contractAddress = await project.getAddress();
  
  console.log("✅ Real Estate Tokenization Contract deployed successfully!");
  console.log("📍 Contract Address:", contractAddress);
  console.log("🌐 Network:", hre.network.name);
  
  // Get deployment transaction details
  const deploymentTx = project.deploymentTransaction();
  if (deploymentTx) {
    console.log("🔗 Deployment Transaction Hash:", deploymentTx.hash);
    console.log("⛽ Gas Used:", deploymentTx.gasLimit.toString());
  }
  
  console.log("\n📝 Contract Verification Info:");
  console.log("Contract Name: Project");
  console.log("Constructor Arguments: None");
  
  if (hre.network.name === "core_testnet2") {
    console.log("\n🔍 You can verify the contract using:");
    console.log(`npx hardhat verify --network core_testnet2 ${contractAddress}`);
    console.log("\n🌐 View on Core Testnet 2 Explorer:");
    console.log(`https://scan.test2.btcs.network/address/${contractAddress}`);
  }
  
  console.log("\n🎉 Deployment completed successfully!");
  
  // Save deployment info to a file
  const fs = require('fs');
  const deploymentInfo = {
    contractAddress: contractAddress,
    network: hre.network.name,
    deploymentTime: new Date().toISOString(),
    transactionHash: deploymentTx ? deploymentTx.hash : null
  };
  
  fs.writeFileSync('deployment-info.json', JSON.stringify(deploymentInfo, null, 2));
  console.log("📄 Deployment info saved to deployment-info.json");
}

// Error handling
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:");
    console.error(error);
    process.exit(1);
  });
