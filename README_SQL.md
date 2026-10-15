# Supermarket Sales Analysis with SQL (PostgreSQL)

An end-to-end SQL project analyzing **6.7 million sales transactions** of a supermarket chain: revenue trends, product performance, and customer behavior.

**Author:** Tran Hoang Phuc
**Tool:** PostgreSQL
**Techniques:** CTEs, Window Functions, Joins, Aggregations, Percentiles, Correlation, Indexing, Data Cleaning

---

## Project Overview

The goal is to evaluate the financial health of the supermarket and turn raw transaction data into business insights. The analysis is organized into three business scenarios:

| Scenario | Focus | Key questions |
|----------|-------|---------------|
| **1. Revenue over time** | Financial performance | How does revenue change month by month? Which categories drive growth and how stable is their share? |
| **2. Product portfolio** | Product ranking & classification | Which products and categories sell best or worst? Which products have high demand but low price? |
| **3. Customer behavior** | Segmentation & basket analysis | Who are the most valuable customers? How many return? What is the average order value (AOV) and basket size? |

---

## Dataset

Seven related tables, loaded from CSV files:

| Table | Rows | Description |
|-------|------|-------------|
| `sales` | ~6.76 million | Transaction lines (product, quantity, discount, date, transaction number) |
| `customers` | ~98,700 | Customer information |
| `products` | ~450 | Product catalog (price, class, category) |
| `employees` | 23 | Sales staff |
| `cities` | 96 | City reference data |
| `countries` | 206 | Country reference data |
| `categories` | 11 | Product categories |

**Schema (simplified):**

```
countries ─< cities ─< customers ─< sales >─ products >─ categories
                  └──< employees ──────┘
```

---

## Data Preparation

- Created tables with **primary and foreign key constraints**, then loaded data using `COPY`.
- Created `sales_backup` before modifying any data.
- Found rows with a missing `SalesDate` (less than 1% of the data) and removed them.
- The `TotalPrice` column was `0` for every row, so it was **recalculated** as `Price × Quantity × (1 − Discount)`.
- Fixed a typo in a column name (`CategogyName` → `CategoryName`).
- Added **indexes** on `sales` (`ProductID`, `CustomerID`, `SalesPersonID`, `SalesDate`) and `customers` (`CityID`) so joins and aggregations on millions of rows run faster.

---

## Analysis Summary

### Scenario 1: Revenue Performance Over Time
- Total revenue, gross revenue before discount, total discount and discount rate.
- Monthly revenue with **month-over-month growth**, cumulative revenue, and revenue per day (to compare partial months fairly).
- Category revenue share by month, rank within month, and share change in percentage points.
- Share stability per category (average, min, max, range, standard deviation).

### Scenario 2: Product Portfolio
- Category ranking with revenue share and **cumulative share**.
- Top 5 best-selling and bottom 5 underperforming products.
- Full product ranking, ready to export to Power BI.
- **Pearson correlation** between units sold, revenue and net unit price, overall and per category.
- Products with top 20% volume but bottom 20% net price (low margin, high demand).
- Four-quadrant classification by demand and price (low-margin, star, niche, candidates for removal).

### Scenario 3: Customer Behavior
- **Segmentation** by frequency and spend (VIP, Loyal, Big spender, Low value), using median thresholds.
- Top 20 most valuable customers for marketing.
- Repeat customers vs one-time buyers and their share of revenue.
- **AOV** and **basket size** overall, by month, and as a distribution.

---

## Key Findings

All findings below come from the queries in this project (query IDs in brackets). The data covers 129 days, from 1 January to 9 May 2018: 6.69M sales lines, total revenue of 4.29 billion, and a 3.00% overall discount (132.5M) [1.1a].

### Scenario 1: Revenue over time
- **Revenue is flat once days are normalized.** Daily revenue stayed between 33.19M and 33.31M in every month [1.1b]. Monthly totals only look volatile (-9.85% in Feb, +11.08% in Mar) because months have different numbers of days. The -69.93% drop in May is a partial month (9 days), which is why the queries flag `is_full_month`.
- **The category mix is even and very stable.** Confections (12.85%), Meat (11.38%) and Poultry (10.16%) lead, and the top 3 together hold 34.39%, while Shell fish is lowest at 6.92% [2.1a]. The rank of all 11 categories did not change in any of the four full months, and each category's share moved by at most 0.16 percentage points (standard deviation 0.02 to 0.06) [1.2a, 1.2b].

### Scenario 2: Product portfolio
- **Demand is almost identical across products, so price decides revenue.** All 452 products sold between 187.8K and 197.8K units (a spread of about 5%), yet product revenue ranges from 8.4K to 18.7M, a gap of about 2,200 times [2.1b, 2.1c]. The top 5 and bottom 5 products sell the same volume (191K to 196K units). Correlation between units sold and revenue is only 0.099, and 0.083 between units and price [2.2a]. At category level it ranges from -0.19 (Shell fish) to 0.32 (Snails) [2.2b].
- **Half of the products generate about three quarters of revenue.** The two higher-price groups (226 products) bring in 74.3% of revenue, while the two lower-price groups (226 products) bring in 25.7% [2.2d]. Splitting by demand instead makes almost no difference (52.5% vs 47.5%).
- **Some high-volume products are sold at very low prices.** Ten products are in the top 20% by volume but the bottom 20% by net price, for example Apricots - Halves (194K units, net price 0.36, revenue only 70K) [2.2c]. They are candidates for a price review. The effective discount is about 3% on every product (2.92% to 3.12%), so the discount is flat and not used to target specific items.

### Scenario 3: Customer behavior
- **Customer segments differ by order value, not by frequency.** Customers place a similar number of orders in every segment (61 to 75), but average order value is about 915 to 980 for VIP and Big-spender customers versus about 300 to 360 for the other two segments [3.1b]. To grow revenue per customer, upselling to higher-priced products is more promising than pushing visit frequency, which matches the product-level finding.
- **The higher-spending half of customers brings in three quarters of revenue.** VIP and Big-spender segments are 50.0% of customers and 74.55% of revenue [3.1b]. The top 20 customers each spend 116K to 127K, roughly 2.7 to 2.9 times the average customer (43.4K) [3.1c].
- **Average order value is stable at 641.08**, within 640.2 to 642.2 every month [3.3a, 3.3b]. The median order is 490.77, so a minority of large orders pulls the average up.

### Data limitations
- **Every order has exactly one line item (basket size 1.00, 13 units per line) and every customer is a repeat customer (100%, 67.75 orders on average)** [3.2, 3.3c]. This suggests each `TransactionNumber` identifies a single sales line, so the basket-size and one-time-buyer analyses carry no information on this dataset, and AOV is effectively the value of one sales line.
- The data looks synthetic and evenly distributed, which explains the flat trends and low concentration. The queries are written to work on real data with stronger patterns.

---

## Repository Structure

```
.
├── Project_1_SQL.sql    # Schema, data cleaning, and all analysis queries
├── Dataset/             # CSV source files (see note below)
└── README.md
```

> **Note:** `sales.csv` has about 6.7 million rows and exceeds GitHub's 100 MB file limit, so it is not included in this repository. See the "How to Run" section for how to get the data.

---

## How to Run

1. Install [PostgreSQL](https://www.postgresql.org/download/) and a client such as pgAdmin or DBeaver.
2. Place the CSV files in a local folder.
3. Open `Project_1_SQL.sql` and update the file paths in each `COPY ... FROM '...'` statement to match your folder.
4. Create a database (`CREATE DATABASE Project_SQL_1;`), connect to it, and run the script from top to bottom.
5. Run the analysis queries in each scenario section individually to see the results.

---

## Skills Demonstrated

- Relational database design with primary and foreign keys
- Data cleaning and validation on a large dataset
- Complex querying: multi-level CTEs, window functions (`RANK`, `LAG`, `PERCENT_RANK`, running totals)
- Statistical functions: `CORR`, `PERCENTILE_CONT`, `STDDEV_SAMP`
- Performance tuning with indexes
- Translating business questions into SQL and metrics (MoM, AOV, basket size, customer segmentation)

---

## Contact

**Tran Hoang Phuc**
GitHub: [PhucTran289](https://github.com/PhucTran289)
