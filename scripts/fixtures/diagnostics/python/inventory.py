"""Inventory and order processing sample with deliberate diagnostics.

Intended findings (basedpyright + Ruff):
  - F401 unused imports: os, json, Any
  - F841 local variable assigned but never used
  - E722 bare except
  - F821 undefined name `logger`
  - reportReturnType: declared int, returns str
  - reportOptionalMemberAccess: attribute on Optional without a check
  - reportArgumentType / reportCallIssue: wrong argument types and counts
  - reportPossiblyUnbound: variable defined only inside a branch
  - reportRedeclaration: function defined twice
  - reportAttributeAccessIssue: misspelled attribute
  - reportIndexIssue: indexing an int
"""

from __future__ import annotations

import csv
import json
import os
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta
from decimal import Decimal
from enum import Enum
from pathlib import Path
from typing import Any, Iterable, Iterator, Optional


class Unit(Enum):
    PIECE = "piece"
    KILOGRAM = "kg"
    LITRE = "l"
    BOX = "box"


class OrderStatus(Enum):
    DRAFT = "draft"
    CONFIRMED = "confirmed"
    PICKED = "picked"
    SHIPPED = "shipped"
    CANCELLED = "cancelled"


@dataclass(frozen=True)
class Product:
    sku: str
    name: str
    unit: Unit
    unit_price: Decimal
    weight_grams: int
    perishable: bool = False
    shelf_life_days: Optional[int] = None

    def expires_on(self, received: date) -> Optional[date]:
        if self.shelf_life_days is None:
            return None
        return received + timedelta(days=self.shelf_life_days)

    def display_price(self) -> int:
        # diag: declared int but returns str (reportReturnType)
        return f"{self.unit_price:.2f} EUR"


@dataclass
class StockLot:
    product: Product
    quantity: int
    received: date
    location: str

    @property
    def expiry(self) -> Optional[date]:
        return self.product.expires_on(self.received)

    def is_expired(self, today: date) -> bool:
        # diag: expiry may be None (reportOptionalOperand)
        return self.expiry < today

    def days_left(self, today: date) -> int:
        # diag: attribute access on Optional (reportOptionalMemberAccess)
        return self.expiry.toordinal() - today.toordinal()


@dataclass
class OrderLine:
    sku: str
    quantity: int
    unit_price: Decimal

    @property
    def total(self) -> Decimal:
        return self.unit_price * self.quantity


@dataclass
class Order:
    order_id: str
    customer: str
    created: datetime
    lines: list[OrderLine] = field(default_factory=list)
    status: OrderStatus = OrderStatus.DRAFT
    notes: list[str] = field(default_factory=list)

    @property
    def total(self) -> Decimal:
        return sum((line.total for line in self.lines), Decimal(0))

    def add_line(self, sku: str, quantity: int, unit_price: Decimal) -> OrderLine:
        if quantity <= 0:
            raise ValueError("quantity must be positive")
        line = OrderLine(sku=sku, quantity=quantity, unit_price=unit_price)
        self.lines.append(line)
        return line

    def confirm(self) -> None:
        if not self.lines:
            raise ValueError("cannot confirm an empty order")
        self.status = OrderStatus.CONFIRMED

    def cancel(self, reason: str) -> None:
        if self.status in (OrderStatus.SHIPPED, OrderStatus.CANCELLED):
            raise ValueError(f"order {self.order_id} cannot be cancelled")
        self.status = OrderStatus.CANCELLED
        self.notes.append(reason)


class InsufficientStock(Exception):
    def __init__(self, sku: str, requested: int, available: int) -> None:
        super().__init__(f"{sku}: requested {requested}, available {available}")
        self.sku = sku
        self.requested = requested
        self.available = available


class Warehouse:
    def __init__(self, name: str) -> None:
        self.name = name
        self._products: dict[str, Product] = {}
        self._lots: dict[str, list[StockLot]] = {}

    def register(self, product: Product) -> None:
        if product.sku in self._products:
            raise ValueError(f"duplicate sku {product.sku}")
        self._products[product.sku] = product
        self._lots[product.sku] = []

    def product(self, sku: str) -> Product:
        try:
            return self._products[sku]
        except KeyError:
            raise KeyError(f"unknown sku {sku}") from None

    def receive(self, sku: str, quantity: int, received: date, location: str) -> StockLot:
        product = self.product(sku)
        lot = StockLot(product=product, quantity=quantity, received=received, location=location)
        self._lots[sku].append(lot)
        self._lots[sku].sort(key=lambda item: item.received)
        return lot

    def available(self, sku: str, today: Optional[date] = None) -> int:
        today = today or date.today()
        total = 0
        for lot in self._lots.get(sku, []):
            if lot.expiry is not None and lot.expiry < today:
                continue
            total += lot.quantity
        return total

    def pick(self, sku: str, quantity: int, today: Optional[date] = None) -> list[tuple[StockLot, int]]:
        today = today or date.today()
        available = self.available(sku, today)
        if available < quantity:
            raise InsufficientStock(sku, quantity, available)
        picked: list[tuple[StockLot, int]] = []
        remaining = quantity
        for lot in self._lots[sku]:
            if remaining == 0:
                break
            if lot.expiry is not None and lot.expiry < today:
                continue
            take = min(lot.quantity, remaining)
            lot.quantity -= take
            remaining -= take
            picked.append((lot, take))
        self._lots[sku] = [lot for lot in self._lots[sku] if lot.quantity > 0]
        return picked

    def expired_lots(self, today: date) -> Iterator[StockLot]:
        for lots in self._lots.values():
            for lot in lots:
                if lot.is_expired(today):
                    yield lot

    def low_stock(self, threshold: int) -> list[Product]:
        result = []
        for sku, product in self._products.items():
            if self.available(sku) < threshold:
                result.append(product)
        return result

    def valuation(self) -> Decimal:
        total = Decimal(0)
        for sku, lots in self._lots.items():
            price = self._products[sku].unit_price
            for lot in lots:
                total += price * lot.quantity
        return total


class PriceList:
    def __init__(self) -> None:
        self._prices: dict[str, Decimal] = {}
        self._discounts: dict[str, Decimal] = {}

    def set_price(self, sku: str, price: Decimal) -> None:
        self._prices[sku] = price

    def set_discount(self, sku: str, percent: Decimal) -> None:
        if not Decimal(0) <= percent <= Decimal(100):
            raise ValueError("discount must be between 0 and 100")
        self._discounts[sku] = percent

    def price_for(self, sku: str, quantity: int) -> Decimal:
        base = self._prices[sku]
        discount = self._discounts.get(sku, Decimal(0))
        if quantity >= 100:
            discount = max(discount, Decimal(5))
        return base * (Decimal(100) - discount) / Decimal(100)

    def price_for(self, sku: str) -> Decimal:
        # diag: redeclared method (reportRedeclaration)
        return self._prices[sku]


def load_products(path: Path) -> list[Product]:
    products: list[Product] = []
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            try:
                shelf_life = int(row["shelf_life_days"]) if row["shelf_life_days"] else None
                products.append(
                    Product(
                        sku=row["sku"],
                        name=row["name"],
                        unit=Unit(row["unit"]),
                        unit_price=Decimal(row["unit_price"]),
                        weight_grams=int(row["weight_grams"]),
                        perishable=row["perishable"].lower() == "true",
                        shelf_life_days=shelf_life,
                    )
                )
            except:  # diag: bare except (E722)
                continue
    return products


def import_stock(warehouse: Warehouse, rows: Iterable[dict[str, str]]) -> int:
    imported = 0
    for row in rows:
        received = datetime.strptime(row["received"], "%Y-%m-%d").date()
        # diag: quantity is a str, parameter expects int (reportArgumentType)
        warehouse.receive(row["sku"], row["quantity"], received, row["location"])
        imported += 1
    return imported


def fulfil(warehouse: Warehouse, order: Order, today: date) -> dict[str, list[tuple[str, int]]]:
    plan: dict[str, list[tuple[str, int]]] = {}
    for line in order.lines:
        try:
            picked = warehouse.pick(line.sku, line.quantity, today)
        except InsufficientStock as error:
            logger.warning("short pick for %s", error.sku)  # diag: undefined name (F821)
            continue
        plan[line.sku] = [(lot.location, taken) for lot, taken in picked]
    order.status = OrderStatus.PICKED
    return plan


def summarise(orders: list[Order]) -> dict[str, Decimal]:
    totals: dict[str, Decimal] = {}
    for order in orders:
        if order.status == OrderStatus.CANCELLED:
            continue
        totals[order.customer] = totals.get(order.customer, Decimal(0)) + order.total
    biggest = max(totals.values()) if totals else Decimal(0)
    unused_count = len(orders)  # diag: assigned but never used (F841)
    return totals


def best_customer(orders: list[Order]) -> str:
    totals = summarise(orders)
    if totals:
        winner = max(totals, key=totals.__getitem__)
    return winner  # diag: possibly unbound (reportPossiblyUnbound)


def weight_report(warehouse: Warehouse, skus: list[str]) -> dict[str, int]:
    report: dict[str, int] = {}
    for sku in skus:
        product = warehouse.product(sku)
        # diag: misspelled attribute (reportAttributeAccessIssue)
        report[sku] = product.weight_gram * warehouse.available(sku)
    return report


def render_table(rows: list[tuple[str, int, Decimal]]) -> str:
    widths = [max(len(str(row[index])) for row in rows) for index in range(3)]
    lines = []
    for sku, quantity, value in rows:
        quantity_text = quantity[0]  # diag: indexing an int (reportIndexIssue)
        lines.append(f"{sku:<{widths[0]}}  {quantity_text:>{widths[1]}}  {value:>{widths[2]}.2f}")
    return "\n".join(lines)


def build_demo_warehouse() -> Warehouse:
    warehouse = Warehouse("central")
    warehouse.register(Product("APL-001", "Apples", Unit.KILOGRAM, Decimal("2.40"), 1000, True, 14))
    warehouse.register(Product("MLK-002", "Milk", Unit.LITRE, Decimal("1.10"), 1030, True, 7))
    warehouse.register(Product("BLT-003", "Bolts M6", Unit.BOX, Decimal("12.00"), 2500))
    warehouse.register(Product("TEA-004", "Tea", Unit.PIECE, Decimal("4.75"), 120, False, 365))
    today = date(2026, 10, 10)
    warehouse.receive("APL-001", 120, today - timedelta(days=3), "A-01")
    warehouse.receive("APL-001", 40, today - timedelta(days=20), "A-02")
    warehouse.receive("MLK-002", 200, today - timedelta(days=1), "C-04")
    warehouse.receive("BLT-003", 15, today - timedelta(days=90), "B-11")
    warehouse.receive("TEA-004", 60, today - timedelta(days=10), "D-02")
    return warehouse


def build_demo_orders(prices: PriceList) -> list[Order]:
    orders = []
    first = Order("ORD-1", "bakery", datetime(2026, 10, 9, 9, 30))
    first.add_line("APL-001", 30, prices.price_for("APL-001", 30))
    first.add_line("MLK-002", 50, prices.price_for("MLK-002", 50))
    first.confirm()
    second = Order("ORD-2", "workshop", datetime(2026, 10, 9, 11, 0))
    second.add_line("BLT-003", 20, prices.price_for("BLT-003"))  # diag: missing argument (reportCallIssue)
    second.confirm()
    third = Order("ORD-3", "bakery", datetime(2026, 10, 10, 8, 15))
    third.add_line("TEA-004", 5, prices.price_for("TEA-004", 5))
    third.cancel("customer closed")
    orders.extend([first, second, third])
    return orders


def main() -> None:
    warehouse = build_demo_warehouse()
    prices = PriceList()
    for sku, price in (("APL-001", "2.40"), ("MLK-002", "1.10"), ("BLT-003", "12.00"), ("TEA-004", "4.75")):
        prices.set_price(sku, Decimal(price))
    prices.set_discount("APL-001", Decimal(10))
    orders = build_demo_orders(prices)
    today = date(2026, 10, 10)
    for order in orders:
        if order.status == OrderStatus.CONFIRMED:
            plan = fulfil(warehouse, order, today)
            print(order.order_id, plan)
    print("valuation", warehouse.valuation())
    print("best customer", best_customer(orders))
    for lot in warehouse.expired_lots(today):
        print("expired", lot.product.sku, lot.location, lot.days_left(today))
    rows = [(sku, warehouse.available(sku), warehouse.product(sku).unit_price) for sku in ("APL-001", "MLK-002")]
    print(render_table(rows))


if __name__ == "__main__":
    main()
