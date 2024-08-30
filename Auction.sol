// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract Auction {

    address payable public Auctioneer;
    uint public stblock; // start time
    uint public edblock; // end time

    uint public bidInc;

    struct Product {
        uint productId;
        string productName;
        address payable owner;
        Auc_State productState;
        uint highestBid;
        uint highestPayableBid;
        address payable highestBidder;
        mapping(address => uint) bids;
        address[] bidders;
    }

    enum Auc_State {Started, Running, Ended, Cancelled}
    mapping(uint => Product) public products;
    uint public productCount;

    constructor() {
        Auctioneer = payable(msg.sender);
        stblock = block.number;
        edblock = stblock + 240;
        bidInc = 0.1 ether;  // Lowered bid increment to 0.1 ether
    }

    modifier notOwner(uint productId) {
        require(msg.sender != products[productId].owner, "Owner cannot bid on their own product");
        _;
    }

    modifier onlyOwner(uint productId) {
        require(msg.sender == products[productId].owner, "Only owner can call this");
        _;
    }

    modifier started(uint productId) {
        require(block.number > stblock, "Auction not started yet");
        require(products[productId].productState == Auc_State.Running, "Auction not running for this product");
        _;
    }

    modifier beforeEnding(uint productId) {
        require(block.number < edblock, "Auction already ended");
        require(products[productId].productState == Auc_State.Running, "Auction not running for this product");
        _;
    }

    modifier productExists(uint productId) {
        require(bytes(products[productId].productName).length != 0, "Product does not exist");
        _;
    }

    function registerProduct(uint productId, string memory productName, uint startingPrice) public {
        require(bytes(products[productId].productName).length == 0, "Product already exists");
        require(startingPrice >= bidInc, "Starting price must be greater than or equal to the bid increment");

        Product storage product = products[productId];
        product.productId = productId;
        product.productName = productName;
        product.owner = payable(msg.sender);
        product.productState = Auc_State.Started;
        product.highestBid = startingPrice;
        product.highestPayableBid = startingPrice;

        productCount++;
    }

    function startAuction(uint productId) public onlyOwner(productId) productExists(productId) {
        products[productId].productState = Auc_State.Running;
    }

    function cancelAuction(uint productId) public onlyOwner(productId) productExists(productId) {
        Product storage product = products[productId];
        require(product.productState == Auc_State.Running, "Auction is not running");

        product.productState = Auc_State.Cancelled;

        // Refund all bidders
        for (uint i = 0; i < product.bidders.length; i++) {
            address bidder = product.bidders[i];
            uint refundValue = product.bids[bidder];
            if (refundValue > 0) {
                product.bids[bidder] = 0;
                payable(bidder).transfer(refundValue);
            }
        }
    }

    function endAuction(uint productId) public onlyOwner(productId) productExists(productId) {
        Product storage product = products[productId];
        require(product.productState == Auc_State.Running, "Auction is not running");
        product.productState = Auc_State.Ended;

        // Transfer the highest payable bid to the current owner
        if (product.highestBidder != address(0)) {
            uint highestPayableBid = product.highestPayableBid;
            require(address(this).balance >= highestPayableBid, "Insufficient contract balance to transfer");
            product.owner.transfer(highestPayableBid);
            
            // Transfer ownership to the highest bidder
            product.owner = product.highestBidder;

            // Refund all bidders except the highest bidder
            for (uint i = 0; i < product.bidders.length; i++) {
                address bidder = product.bidders[i];
                if (bidder != product.highestBidder) {
                    uint refundValue = product.bids[bidder];
                    if (refundValue > 0) {
                        payable(bidder).transfer(refundValue);
                        product.bids[bidder] = 0;
                    }
                }
            }
        }
    }

    function bid(uint productId) payable public notOwner(productId) started(productId) beforeEnding(productId) {
        Product storage product = products[productId];
        require(msg.value >= (product.highestPayableBid + bidInc), "There already is a higher bid");
        uint currentBid = msg.value;
        if (product.bids[msg.sender] == 0) {
            product.bidders.push(msg.sender);  // Track the bidder if they are bidding for the first time
        }

        product.bids[msg.sender] = currentBid;
        product.highestPayableBid = currentBid;
        product.highestBidder = payable(msg.sender);
    }

    function min(uint a, uint b) pure private returns (uint) {
        return a <= b ? a : b;
    }

    function relistProduct(uint productId) public onlyOwner(productId) productExists(productId) {
        Product storage product = products[productId];
        require(product.productState == Auc_State.Ended, "Auction must be ended before relisting");

        // Reset auction-specific variables
        product.productState = Auc_State.Started;
        product.highestBid = 0;
        product.highestPayableBid = 0;
        product.highestBidder = payable(address(0));

        // Clear previous bids and bidders
        for (uint i = 0; i < product.bidders.length; i++) {
            address bidder = product.bidders[i];
            product.bids[bidder] = 0;
        }
        delete product.bidders;
    }
}
