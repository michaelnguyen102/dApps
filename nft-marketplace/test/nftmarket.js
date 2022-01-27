const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("NFT-Market", function () {
  it("Should create and execute market sales", async function () {
    //Deploy the marketplace
    const Market = await ethers.getContractFactory("NFTMarket");
    const market = await Market.deploy();
    await market.deployed();
    const marketAddress = market.address;

    //Deploy the NFT contract
    const NFT = await ethers.getContractFactory("NFT");
    const nft = await NFT.deploy(marketAddress);
    await nft.deployed();
    const nftContractAddress = nft.address;

    let listingPrice = await market.getListingPrice();
    listingPrice = listingPrice.toString();

    const auctionPrice = ethers.utils.parseUnits('100', 'ether');

    await nft.createToken("https://mytoken1.com");
    await nft.createToken("https://mytoken2.com");

    //put for sales
    await market.createMarketItem(nftContractAddress, 1, auctionPrice, {value: listingPrice});
    await market.createMarketItem(nftContractAddress, 2, auctionPrice, {value: listingPrice});

    //Generate mock buyer addresses
    const [_, buyer1] = await ethers.getSigners();

    /* execute sale of token to another user */
    await market.connect(buyer1).createMarketSale(nftContractAddress, 1, { value: auctionPrice});

    /* query for and return the unsold items */
    let items = await market.fetchMarketItems();

    items = await Promise.all(items.map(async i => {
      const tokenUri = await nft.tokenURI(i.tokenId);
      let item = {
        price: i.price.toString(),
        tokenId: i.tokenId.toString(),
        seller: i.seller,
        owner: i.owner,
        tokenUri
      }
      return item;
    }))

    console.log('items: ', items);
  });
});
