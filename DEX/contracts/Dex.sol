// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract Dex {
    using SafeMath for uint;

    struct Token {
        bytes32 ticker;
        address tokenAddress;
    }
    enum Side {
        BUY,
        SELL
    }
    struct Order {
        uint id;
        address trader;
        Side side;
        bytes32 ticker;
        uint amount;
        uint filled; //how much of the amount is filled - full or partial filled order
        uint price;
        uint date;
    }

    mapping(bytes32 => Token) public tokens;
    bytes32[] public tokenList;
    //keep tract of balances of tokens from traders
    mapping(address => mapping(bytes32 => uint)) public traderBalances;
    //ticker => 0/1 (Buy/Sell) => array of order
    //Buy (60,50,50,32) - buy highest price first (users)
    //Sell (60, 67, 70, 72] - sell at the lowest price (users)
    mapping(bytes32 => mapping(uint => Order[])) public orderBook;
    address public admin;
    uint public nextOrderId;
    uint public nextTradeId;
    bytes32 constant DAI = bytes32('DAI');

    //Get orderbook
    function getOrders(
        bytes32 ticker,
        Side side)
        external view returns(Order[] memory)
    {
        return orderBook[ticker][uint(side)];
    }

    //Get token list
    function getTokens() external view returns(Token[] memory) {
        Token[] memory _tokens = new Token[](tokenList.length);
        for(uint i=0; i < tokenList.length; i++) {
            _tokens[i] = Token(
                            tokens[tokenList[i]].ticker,
                            tokens[tokenList[i]].tokenAddress);
        }
        return _tokens;
    }

    event NewTrade (
        uint tradeId,
        uint orderId,
        bytes32 indexed ticker,
        address indexed trader1,
        address indexed trader2,
        uint amount,
        uint price,
        uint date
    );

    constructor() {
        admin = msg.sender;
    }

    function addToken(bytes32 ticker, address tokenAddress) onlyAdmin() external {
        tokens[ticker] = Token(ticker, tokenAddress);
        tokenList.push(ticker);
    }

    function deposit(
        uint amount,
        bytes32 ticker)
        tokenExists(ticker)
     external {
        IERC20(tokens[ticker].tokenAddress).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        traderBalances[msg.sender][ticker] = traderBalances[msg.sender][ticker].add(amount);
    }

    function withdraw(
        uint amount,
        bytes32 ticker)
        tokenExists(ticker)
     external {
         
         require(traderBalances[msg.sender][ticker] >= amount,
         'balance too low');
         
        traderBalances[msg.sender][ticker] = traderBalances[msg.sender][ticker].sub(amount);
        IERC20(tokens[ticker].tokenAddress).transfer(
            msg.sender,            
            amount
        );
    }

    function createLimitOrder(
        bytes32 ticker,
        uint amount,
        uint price,
        Side side)
        tokenExists(ticker)
        tokenIsNotDai(ticker)
        external {

        //check for sufficient balance
        if (side == Side.SELL)
            require(
                traderBalances[msg.sender][ticker] >= amount,
                'token balance too low'
            );
        else {
            //for BUY order, make sure user has enough DAI balance
            require(
                traderBalances[msg.sender][DAI] >= amount.mul(price),
                'DAI balance too low'
            );
        }

        //get a snapshot of order
        Order[] storage orders = orderBook[ticker][uint(side)];

        //Create order
        orders.push(Order(
            nextOrderId,
            msg.sender,
            side,
            ticker,
            amount,
            0,
            price,
            block.timestamp
        ));

        //sorting
        uint i = orders.length > 0 ? orders.length - 1 : 0;
        while (i > 0) {
            //FOR BUY order, big number show up first
            if (side == Side.BUY && orders[i-1].price > orders[i].price) 
                break;

            //For SELL order, small number shows up first
            if (side == Side.SELL && orders[i-1].price < orders[i].price) 
                break;
            //Swap
            Order memory order = orders[i-1];
            orders[i-1] = orders[i];
            orders[i] = order;
            i.sub(1);    
        }
        nextOrderId.add(1);
    }
    
    function createMarketOrder(
        bytes32 ticker,
        uint amount,
        Side side)
        tokenExists(ticker)
        tokenIsNotDai(ticker)
        external
    {
        if (side == Side.SELL)
            require(
                traderBalances[msg.sender][ticker] >= amount,
                'token balance too low'
            );
        //Get the opposite order book - if it's a buy order, get the sell orderbook because we need to match buy-sell
        Order[] storage orders = orderBook[ticker][uint(side == Side.BUY ? Side.SELL : Side.BUY)];
        uint i;
        uint remaining = amount;

        //start matching process until we find a match
        while (i < orders.length && remaining > 0) {
            //Find out the available liquidity of each order from the order book
            //Delta between the amount and filled
            uint available = orders[i].amount.sub(orders[i].filled);
            uint matched = (remaining > available) ? available : remaining;
            remaining = remaining.sub(matched);
            //update the filled 
            orders[i].filled = orders[i].filled.add(matched);
            //call event
            emit NewTrade(
                nextTradeId,
                orders[i].id,
                ticker,
                orders[i].trader,
                msg.sender,
                matched,
                orders[i].price,
                block.timestamp
            );

            //Update the balances for buyer and seller
            if (side == Side.SELL) {
                //For seller
                //1. Substract the sold token
                traderBalances[msg.sender][ticker] = traderBalances[msg.sender][ticker].sub(matched);
                //2. Add the equivalent DAI from selling
                traderBalances[msg.sender][DAI] = traderBalances[msg.sender][DAI].add(matched * orders[i].price);
                //For Buyer from orderbook
                //1. Increase the amount
                traderBalances[orders[i].trader][ticker] = traderBalances[orders[i].trader][ticker].add(matched);
                //2. Decrease the DAI
                traderBalances[orders[i].trader][DAI] = traderBalances[orders[i].trader][DAI].sub(matched * orders[i].price);
            }
            else { //BUY side
                //check if buyer has enough DAI for the transaction
                require(traderBalances[msg.sender][DAI] >= matched.mul(orders[i].price),
                    'DAI balance too low');

                //For buyer
                //1. Add the bought token
                traderBalances[msg.sender][ticker] = traderBalances[msg.sender][ticker].add(matched);
                //2. Substract the equivalent DAI from buying
                traderBalances[msg.sender][DAI] = traderBalances[msg.sender][DAI].sub(matched * orders[i].price);
                //For seller from orderbook
                //1. Decrease the amount
                traderBalances[orders[i].trader][ticker] = traderBalances[orders[i].trader][ticker].sub(matched);
                //2. Increase the DAI
                traderBalances[orders[i].trader][DAI] = traderBalances[orders[i].trader][DAI].add(matched * orders[i].price);
            }
            nextTradeId = nextTradeId.add(1);
            i = i.add(1);
        }

        //Remove 100% filled order from orderbook
        i = 0;
        while (i < orders.length && orders[i].filled == orders[i].amount) {
            for (uint j = i; j < orders.length-1; j++) {
                orders[j] = orders[j+1];
            }
            orders.pop();
            i = i.add(1);
        }
    }

    modifier tokenIsNotDai(bytes32 token) {
        require(token != DAI, 'cannot trade DAI');
        _;
    }

    modifier tokenExists(bytes32 ticker) {
        require(tokens[ticker].tokenAddress != address(0),
                'this token does not exist'
        );
        _;
    }
    modifier onlyAdmin() {
        require(msg.sender == admin, 'only admin');
        _;
    }
}
