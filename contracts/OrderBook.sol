// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./interfaces/IOrderBook.sol";
import "./interfaces/IOrderFillCallback.sol";

import "./library/FullMath.sol";

/// @title Order Book
contract OrderBook is IOrderBook {
    using Counters for Counters.Counter;
    using MinLinkedListLib for MinLinkedList;
    using MaxLinkedListLib for MaxLinkedList;
    using SafeMath for uint256;
    /// Linked list of ask orders sorted by orders with the lowest prices
    /// coming first
    MinLinkedList ask;
    /// Linked list of bid orders sorted by orders with the highest prices
    /// coming first
    MaxLinkedList bid;
    /// The order id of the last order created
    Counters.Counter private _orderIdCounter;

    /// @notice The addres that deployed the order book
    address public owner;
    /// @notice The address of the router for this order book
    address public routerAddress;

    uint8 public immutable orderBookId;
    IERC20Metadata public immutable token0;
    IERC20Metadata public immutable token1;
    uint256 public immutable sizeTick;
    uint256 public immutable priceTick;
    uint256 public priceMultiplier;

    /// @notice Emitted whenever a limit order is created
    event LimitOrderCreated(
        uint32 indexed id,
        address indexed owner,
        uint256 amount0,
        uint256 amount1,
        bool isAsk
    );

    /// @notice Emitted whenever a limit order is updated
    event LimitOrderUpdated(
        uint32 indexed id,
        address indexed owner,
        uint256 newAmount0,
        uint256 newAmount1,
        bool isAsk
    );

    /// @notice Emitted whenever a limit order is canceled
    event LimitOrderCanceled(
        uint32 indexed id,
        address indexed owner,
        uint256 amount0,
        uint256 amount1,
        bool isAsk
    );

    /// @notice Emitted whenever a market order is created
    event MarketOrderCreated(
        uint32 indexed id,
        address indexed owner,
        uint256 amount0,
        uint256 amount1,
        bool isAsk
    );

    /// @notice Emitted whenever a swap between two orders occurs. This
    /// happens when orders are being filled
    event Swap(
        uint256 amount0,
        uint256 amount1,
        uint32 indexed askId,
        address askOwner,
        uint32 indexed bidId,
        address bidOwner
    );

    function checkIsRouter() private view {
        require(
            msg.sender == routerAddress,
            "Only the router contract can call this function"
        );
    }

    modifier onlyRouter() {
        checkIsRouter();
        _;
    }

    constructor(
        uint8 _orderBookId,
        address token0Address,
        address token1Address,
        address _routerAddress,
        uint256 logSizeTick,
        uint256 logPriceTick
    ) {
        token0 = IERC20Metadata(token0Address);
        token1 = IERC20Metadata(token1Address);
        owner = msg.sender;
        routerAddress = _routerAddress;
        require(logSizeTick <= 38, "_logSizeTick is too big");
        require(logPriceTick <= 38, "_logPriceTick is too big");
        require(
            logSizeTick + logPriceTick >= token0.decimals(),
            "Invalid size and price tick combination"
        );
        sizeTick = 10 ** logSizeTick;
        priceTick = 10 ** logPriceTick;
        orderBookId = _orderBookId;
        priceMultiplier = FullMath.mulDiv(
            priceTick,
            sizeTick,
            10 ** (token0.decimals())
        );
        setupOrderBook();
    }

    function setupOrderBook() internal {
        ask.list[0] = Node({prev: 0, next: 1, active: true});
        ask.list[1] = Node({prev: 0, next: 1, active: true});
        // Order id 0 is a dummy value and has the lowest possible price
        // in the ask linked list
        ask.idToLimitOrder[0] = LimitOrder({
            id: 0,
            owner: address(0),
            amount0: 1,
            amount1: 0
        });
        // Order id 1 is a dummy value and has the highest possible price
        // in the ask linked list
        ask.idToLimitOrder[1] = LimitOrder({
            id: 1,
            owner: address(0),
            amount0: 0,
            amount1: 1
        });

        bid.list[0] = Node({prev: 0, next: 1, active: true});
        bid.list[1] = Node({prev: 0, next: 1, active: true});
        // Order id 0 is a dummy value and has the highest possible price
        // in the bid linked list
        bid.idToLimitOrder[0] = LimitOrder({
            id: 0,
            owner: address(0),
            amount0: 0,
            amount1: 1
        });
        // Order id 1 is a dummy value and has the lowest possible price
        // in the bid linked list
        bid.idToLimitOrder[1] = LimitOrder({
            id: 1,
            owner: address(0),
            amount0: 1,
            amount1: 0
        });

        _orderIdCounter.increment();
    }

    /// @notice Check if an order is an ask order or a bid order
    /// @dev Does not work for orders with id 0 or 1, since those are
    /// dummy orders
    /// @param id The id of the order to check
    /// @return True if the order is an ask order, false otherwise
    function isAskOrder(uint32 id) private view returns (bool) {
        require(
            ask.idToLimitOrder[id].owner != address(0) ||
                bid.idToLimitOrder[id].owner != address(0),
            "Given order does not exist"
        );
        return ask.idToLimitOrder[id].owner != address(0);
    }

    /// @notice Fill a limit order with existing orders in the order book if
    /// there is a price overlap
    /// @param order The limit order to fill
    /// @param isAsk Whether the order is an ask order
    /// @param from The address of the order sender
    function fillLimitOrder(
        LimitOrder memory order,
        bool isAsk,
        address from
    ) private {
        uint256 filledAmount0;
        uint256 filledAmount1;

        uint32 index;

        if (isAsk) {
            IOrderFillCallback(msg.sender).subtractBalanceCallback(
                token0,
                from,
                order.amount0,
                token1,
                true
            );

            bool atLeastOneFullSwap = false;

            index = bid.getFirstNode();
            while (index != 1 && order.amount0 > 0) {
                LimitOrder storage bestBid = bid.idToLimitOrder[index];
                (
                    uint256 swapAmount0,
                    uint256 swapAmount1
                ) = getLimitOrderSwapAmounts(order, bestBid, isAsk);
                // Since the linked list is sorted, if there is no price
                // overlap on the current order, there will be no price
                // overlap on the later orders
                if (swapAmount0 == 0 || swapAmount1 == 0) break;

                emit Swap(
                    swapAmount0,
                    swapAmount1,
                    order.id,
                    from,
                    bestBid.id,
                    bestBid.owner
                );

                IOrderFillCallback(msg.sender).addBalanceCallback(
                    token0,
                    bestBid.owner,
                    swapAmount0,
                    token1,
                    true
                );
                filledAmount0 = filledAmount0.add(swapAmount0);
                filledAmount1 = filledAmount1.add(swapAmount1);

                require(
                    order.amount1.mul(swapAmount0) % order.amount0 == 0,
                    "Matched amount failed for price tick"
                );
                order.amount1 = order.amount1.sub(
                    FullMath.mulDiv(order.amount1, swapAmount0, order.amount0)
                );
                order.amount0 = order.amount0.sub(swapAmount0);
                if (bestBid.amount0 == swapAmount0) {
                    // Remove the best bid from the order book if it is fully
                    // filled
                    atLeastOneFullSwap = true;
                    bid.list[index].active = false;
                    delete bid.idToLimitOrder[bestBid.id];
                } else {
                    // Update the best bid if it is partially filled
                    bestBid.amount0 = bestBid.amount0.sub(swapAmount0);
                    bestBid.amount1 = bestBid.amount1.sub(swapAmount1);
                    break;
                }

                index = bid.list[index].next;
            }
            if (atLeastOneFullSwap) {
                bid.list[index].prev = 0;
                bid.list[0].next = index;
            }

            if (filledAmount0 > 0) {
                IOrderFillCallback(msg.sender).addBalanceCallback(
                    token1,
                    from,
                    filledAmount1,
                    token0,
                    false
                );
            }
        } else {
            uint256 firstAmount1 = order.amount1;
            IOrderFillCallback(msg.sender).subtractBalanceCallback(
                token1,
                from,
                order.amount1,
                token0,
                false
            );

            bool atLeastOneFullSwap = false;

            index = ask.getFirstNode();
            while (index != 1 && order.amount1 > 0) {
                LimitOrder storage bestAsk = ask.idToLimitOrder[index];
                (
                    uint256 swapAmount0,
                    uint256 swapAmount1
                ) = getLimitOrderSwapAmounts(order, bestAsk, isAsk);
                // Since the linked list is sorted, if there is no price
                // overlap on the current order, there will be no price
                // overlap on the later orders
                if (swapAmount0 == 0 || swapAmount1 == 0) break;

                emit Swap(
                    swapAmount0,
                    swapAmount1,
                    bestAsk.id,
                    bestAsk.owner,
                    order.id,
                    from
                );

                IOrderFillCallback(msg.sender).addBalanceCallback(
                    token1,
                    bestAsk.owner,
                    swapAmount1,
                    token0,
                    false
                );
                filledAmount0 = filledAmount0.add(swapAmount0);
                filledAmount1 = filledAmount1.add(swapAmount1);

                require(
                    order.amount1.mul(swapAmount0) % order.amount0 == 0,
                    "Matched amount failed for price tick"
                );

                order.amount1 = order.amount1.sub(
                    FullMath.mulDiv(order.amount1, swapAmount0, order.amount0)
                );
                order.amount0 = order.amount0.sub(swapAmount0);

                if (bestAsk.amount0 == swapAmount0) {
                    // Remove the best ask from the order book if it is fully
                    // filled
                    atLeastOneFullSwap = true;
                    ask.list[index].active = false;
                    delete ask.idToLimitOrder[bestAsk.id];
                } else {
                    // Update the best ask if it is partially filled
                    bestAsk.amount0 = bestAsk.amount0.sub(swapAmount0);
                    bestAsk.amount1 = bestAsk.amount1.sub(swapAmount1);
                    break;
                }

                index = ask.list[index].next;
            }
            if (atLeastOneFullSwap) {
                ask.list[index].prev = 0;
                ask.list[0].next = index;
            }

            uint256 refundAmount1 = firstAmount1.sub(order.amount1).sub(
                filledAmount1
            );

            if (refundAmount1 > 0) {
                IOrderFillCallback(msg.sender).addBalanceCallback(
                    token1,
                    from,
                    refundAmount1,
                    token0,
                    false
                );
            }

            if (filledAmount0 > 0) {
                IOrderFillCallback(msg.sender).addBalanceCallback(
                    token0,
                    from,
                    filledAmount0,
                    token1,
                    true
                );
            }
        }
    }

    /// @inheritdoc IOrderBook
    function createLimitOrder(
        uint256 amount0Base,
        uint256 priceBase,
        bool isAsk,
        address from,
        uint32 hintId
    ) external override onlyRouter returns (uint32 newOrderId) {
        require(hintId <= _orderIdCounter.current(), "Invalid hint id");
        require(amount0Base > 0, "Invalid size");
        require(priceBase > 0, "Invalid price");
        uint256 amount0 = amount0Base.mul(sizeTick);
        uint256 amount1 = priceBase.mul(amount0Base).mul(priceMultiplier);
        _orderIdCounter.increment();
        require(
            _orderIdCounter.current() < 2 ** 32,
            "New order id exceeds limit"
        );
        newOrderId = uint32(_orderIdCounter.current());

        LimitOrder memory newOrder = LimitOrder(
            newOrderId,
            from,
            amount0,
            amount1
        );

        emit LimitOrderCreated(
            newOrderId,
            from,
            newOrder.amount0,
            newOrder.amount1,
            isAsk
        );

        fillLimitOrder(newOrder, isAsk, from);

        if (isAsk) {
            if (newOrder.amount0 > 0) {
                ask.idToLimitOrder[newOrderId] = newOrder;
                ask.insert(newOrderId, hintId);
            }
        } else {
            if (newOrder.amount0 > 0) {
                bid.idToLimitOrder[newOrderId] = newOrder;
                bid.insert(newOrderId, hintId);
            }
        }
    }

    /// @inheritdoc IOrderBook
    function updateLimitOrder(
        uint32 id,
        uint256 newAmount0Base,
        uint256 newPriceBase,
        address from,
        uint32 hintId
    ) external override onlyRouter returns (bool) {
        require(newAmount0Base > 0, "Invalid size");
        require(newPriceBase > 0, "Invalid price");
        if (!isOrderActive(id)) {
            return false;
        }

        bool isAsk = isAskOrder(id);
        LimitOrder memory order = isAsk
            ? ask.idToLimitOrder[id]
            : bid.idToLimitOrder[id];
        require(
            order.owner == from,
            "The caller should be the owner of the order"
        );

        uint256 _newAmount0 = newAmount0Base.mul(sizeTick);
        uint256 _newAmount1 = newPriceBase.mul(newAmount0Base).mul(
            priceMultiplier
        );

        if (isAsk) {
            if (_newAmount0 > order.amount0) {
                IOrderFillCallback(msg.sender).subtractBalanceCallback(
                    token0,
                    from,
                    _newAmount0.sub(order.amount0),
                    token1,
                    true
                );
            }
            if (_newAmount0 < order.amount0) {
                IOrderFillCallback(msg.sender).addBalanceCallback(
                    token0,
                    from,
                    order.amount0.sub(_newAmount0),
                    token1,
                    true
                );
            }
        } else {
            if (_newAmount1 > order.amount1) {
                IOrderFillCallback(msg.sender).subtractBalanceCallback(
                    token1,
                    from,
                    _newAmount1.sub(order.amount1),
                    token0,
                    false
                );
            }
            if (_newAmount1 < order.amount1) {
                IOrderFillCallback(msg.sender).addBalanceCallback(
                    token1,
                    from,
                    order.amount1.sub(_newAmount1),
                    token0,
                    false
                );
            }
        }

        order.amount0 = _newAmount0;
        order.amount1 = _newAmount1;
        emit LimitOrderUpdated(id, from, order.amount0, order.amount1, isAsk);

        fillLimitOrder(order, isAsk, from);

        if (isAsk) {
            ask.idToLimitOrder[id] = order;
            if (order.amount0 > 0) {
                ask.update(id, hintId);
            } else {
                ask.erase(id);
            }
        } else {
            bid.idToLimitOrder[id] = order;
            if (order.amount0 > 0) {
                bid.update(id, hintId);
            } else {
                bid.erase(id);
            }
        }
        return true;
    }

    /// @inheritdoc IOrderBook
    function cancelLimitOrder(
        uint32 id,
        address from
    ) external override onlyRouter returns (bool) {
        if (!isOrderActive(id)) {
            return false;
        }

        LimitOrder memory order;
        bool isAsk = isAskOrder(id);
        if (isAsk) {
            order = ask.idToLimitOrder[id];
            require(
                order.owner == from,
                "The caller should be the owner of the order"
            );
            IOrderFillCallback(msg.sender).addBalanceCallback(
                token0,
                from,
                ask.idToLimitOrder[id].amount0,
                token1,
                true
            );
            ask.erase(id);
            delete ask.idToLimitOrder[id];
        } else {
            order = bid.idToLimitOrder[id];
            require(
                order.owner == from,
                "The caller should be the owner of the order"
            );
            IOrderFillCallback(msg.sender).addBalanceCallback(
                token1,
                from,
                bid.idToLimitOrder[id].amount1,
                token0,
                false
            );
            bid.erase(id);
            delete bid.idToLimitOrder[id];
        }

        emit LimitOrderCanceled(id, from, order.amount0, order.amount1, isAsk);
        return true;
    }

    /// @inheritdoc IOrderBook
    function createMarketOrder(
        uint256 amount0Base,
        uint256 priceBase,
        bool isAsk,
        address from
    ) external override onlyRouter {
        require(amount0Base > 0, "Invalid size");
        require(priceBase > 0, "Invalid price");
        uint256 amount0 = amount0Base.mul(sizeTick);
        uint256 amount1 = priceBase.mul(amount0Base).mul(priceMultiplier);

        _orderIdCounter.increment();
        require(
            _orderIdCounter.current() < 2 ** 32,
            "New order id exceeds limit"
        );
        uint32 newOrderId = uint32(_orderIdCounter.current());

        LimitOrder memory newOrder = LimitOrder(
            newOrderId,
            from,
            amount0,
            amount1
        );

        emit MarketOrderCreated(
            newOrderId,
            from,
            newOrder.amount0,
            newOrder.amount1,
            isAsk
        );

        fillLimitOrder(newOrder, isAsk, from);

        if (isAsk) {
            IOrderFillCallback(msg.sender).addBalanceCallback(
                token0,
                from,
                newOrder.amount0,
                token1,
                true
            );
        } else {
            IOrderFillCallback(msg.sender).addBalanceCallback(
                token1,
                from,
                newOrder.amount1,
                token0,
                false
            );
        }
    }

    /// @notice Return the minimum between two uints
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a <= b ? a : b;
    }

    /// @notice Get the amount of token0 and token1 to traded between
    /// two orders
    /// @param takerOrder The order taking liquidity from the order book
    /// @param makerOrder The order which already exists in the order book
    /// providing liquidity
    /// @param isAsk Whether the takerOrder is an ask order. If the takerOrder
    /// is an ask order, then the makerOrder must be a bid order and vice versa
    /// @return The amount of token0 and token1 to be traded
    function getLimitOrderSwapAmounts(
        LimitOrder memory takerOrder,
        LimitOrder memory makerOrder,
        bool isAsk
    ) internal pure returns (uint256, uint256) {
        // Default is 0 if there is no price overlap
        uint256 amount0Return = 0;
        uint256 amount1Return = 0;

        // If the takerOrder is an ask, and the makerOrder price is at least
        // the takerOrder's price, then the takerOrder can be filled
        // If the takerOrder is a bid, and the makerOrder price is at most
        // the takerOrder's price, then the takerOrder can be filled
        if (
            (isAsk &&
                !FullMath.mulCompare(
                    takerOrder.amount0,
                    makerOrder.amount1,
                    makerOrder.amount0,
                    takerOrder.amount1
                )) ||
            (!isAsk &&
                !FullMath.mulCompare(
                    makerOrder.amount0,
                    takerOrder.amount1,
                    takerOrder.amount0,
                    makerOrder.amount1
                ))
        ) {
            amount0Return = min(takerOrder.amount0, makerOrder.amount0);
            // The price traded at is the makerOrder's price
            amount1Return = FullMath.mulDiv(
                amount0Return,
                makerOrder.amount1,
                makerOrder.amount0
            );
        }

        return (amount0Return, amount1Return);
    }

    /// @inheritdoc IOrderBook
    function getLimitOrders()
        external
        view
        override
        onlyRouter
        returns (
            uint32[] memory,
            address[] memory,
            uint256[] memory,
            uint256[] memory,
            bool[] memory
        )
    {
        LimitOrder[] memory asks = ask.getOrders();
        LimitOrder[] memory bids = bid.getOrders();

        uint32[] memory ids = new uint32[](asks.length + bids.length);
        address[] memory owners = new address[](asks.length + bids.length);
        uint256[] memory amount0s = new uint256[](asks.length + bids.length);
        uint256[] memory amount1s = new uint256[](asks.length + bids.length);
        bool[] memory isAsks = new bool[](asks.length + bids.length);

        for (uint32 i; i < asks.length; i++) {
            ids[i] = asks[i].id;
            owners[i] = asks[i].owner;
            amount0s[i] = asks[i].amount0;
            amount1s[i] = asks[i].amount1;
            isAsks[i] = true;
        }

        for (uint32 i; i < bids.length; i++) {
            ids[asks.length + i] = bids[i].id;
            owners[asks.length + i] = bids[i].owner;
            amount0s[asks.length + i] = bids[i].amount0;
            amount1s[asks.length + i] = bids[i].amount1;
            isAsks[asks.length + i] = false;
        }

        return (ids, owners, amount0s, amount1s, isAsks);
    }

    /// @inheritdoc IOrderBook
    function getBestAsk()
        external
        view
        override
        onlyRouter
        returns (LimitOrder memory)
    {
        return ask.getTopLimitOrder();
    }

    /// @inheritdoc IOrderBook
    function getBestBid()
        external
        view
        override
        onlyRouter
        returns (LimitOrder memory)
    {
        return bid.getTopLimitOrder();
    }

    /// @inheritdoc IOrderBook
    function isOrderActive(
        uint32 id
    ) public view override onlyRouter returns (bool) {
        return ask.list[id].active || bid.list[id].active;
    }

    /// @inheritdoc IOrderBook
    function getMockIndexToInsert(
        uint256 amount0,
        uint256 amount1,
        bool isAsk
    ) external view override returns (uint32) {
        require(amount0 > 0, "Amount0 must be greater than 0");
        if (isAsk) {
            return ask.getMockIndexToInsert(amount0, amount1);
        } else {
            return bid.getMockIndexToInsert(amount0, amount1);
        }
    }
}
