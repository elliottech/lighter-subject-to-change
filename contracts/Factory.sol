// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./interfaces/IFactory.sol";

import "./OrderBook.sol";
import "./NoDelegateCall.sol";

/// @title Canonical factory
/// @notice Deploys order book and manages ownership
contract Factory is IFactory {
    using Counters for Counters.Counter;

    address public override owner;
    address public router;
    Counters.Counter private _orderBookIdCounter;
    mapping(address => mapping(address => address)) private orderBooksByTokens;
    mapping(uint8 => address) private orderBooksById;

    struct Market {
        address token0;
        address token1;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function");
        _;
    }

    constructor(address _owner) {
        owner = _owner;
    }

    /// @inheritdoc IFactory
    function getOrderBook(address token0, address token1)
        external
        view
        override
        returns (address)
    {
        return orderBooksByTokens[token0][token1];
    }

    /// @notice Returns the address of the order book for the given order book id
    /// @param orderBookId The id of the order book to lookup
    /// @return The address of the order book
    function getOrderBook(uint8 orderBookId)
        external
        view
        override
        returns (address)
    {
        return orderBooksById[orderBookId];
    }

    /// @inheritdoc IFactory
    function getOrderBookDetails(address _token0, address _token1)
        external
        view
        override
        returns (
            uint8 orderBookId,
            address orderBookAddress,
            address token0,
            address token1,
            uint256 sizeTick,
            uint256 priceTick
        )
    {
        orderBookAddress = orderBooksByTokens[_token0][_token1];
        if (orderBookAddress != address(0)) {
            IOrderBook orderBook = IOrderBook(orderBookAddress);
            orderBookId = orderBook.orderBookId();
            token0 = _token0;
            token1 = _token1;
            sizeTick = orderBook.sizeTick();
            priceTick = orderBook.priceTick();
        }
    }

    /// @inheritdoc IFactory
    function getOrderBookDetails(uint8 _orderBookId)
        external
        view
        override
        returns (
            uint8 orderBookId,
            address orderBookAddress,
            address token0,
            address token1,
            uint256 sizeTick,
            uint256 priceTick
        )
    {
        orderBookAddress = orderBooksById[_orderBookId];
        if (orderBookAddress != address(0)) {
            IOrderBook orderBook = IOrderBook(orderBookAddress);
            orderBookId = _orderBookId;
            token0 = address(orderBook.token0());
            token1 = address(orderBook.token1());
            sizeTick = orderBook.sizeTick();
            priceTick = orderBook.priceTick();
        }
    }

    // @inheritdoc IFactory
    function createOrderBook(
        address token0,
        address token1,
        uint256 logSizeTick,
        uint256 logPriceTick
    ) external override onlyOwner returns (address orderBookAddress) {
        require(token0 != token1);
        require(token0 != address(0));
        require(token1 != address(0));

        require(router != address(0), "Router address is not set");

        require(
            orderBooksByTokens[token0][token1] == address(0),
            "Order book already exists"
        );
        uint8 orderBookId = uint8(_orderBookIdCounter.current());

        orderBookAddress = address(
            new OrderBook(
                orderBookId,
                token0,
                token1,
                router,
                logSizeTick,
                logPriceTick
            )
        );

        orderBooksByTokens[token0][token1] = orderBookAddress;
        orderBooksById[orderBookId] = orderBookAddress;
        _orderBookIdCounter.increment();
        require(
            _orderBookIdCounter.current() < 256,
            "Can not create order book"
        );

        emit OrderBookCreated(
            orderBookId,
            orderBookAddress,
            token0,
            token1,
            logSizeTick,
            logPriceTick
        );
    }

    /// @inheritdoc IFactory
    function setRouterAddress(address routerAddress) external override {
        require(router == address(0), "Router address is already set");
        router = routerAddress;
    }
}
