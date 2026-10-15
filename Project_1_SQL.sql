----------------------------
--Tạo database cho project
----------------------------
CREATE DATABASE Project_SQL_1; 

-- Tạo các bảng có trong database
create table categories (
	CategoryID INT, 
	CategogyName VARCHAR(45),
	CONSTRAINT PK_CATE PRIMARY KEY (CategoryID)
);
copy categories 
from 'D:/DOCUMENTS/PROJECT_1/Dataset/categories.csv'
WITH (
    FORMAT csv,
    HEADER true,
    DELIMITER ','
);

create table countries (
	CountryID INT, 
	CountryName VARCHAR(45),
	CountryCode VARCHAR(2), 
	constraint PK_CTRY primary key (CountryID)
);
copy countries
from 'D:/DOCUMENTS/PROJECT_1/Dataset/countries.csv'
WITH (
    FORMAT csv,
    HEADER true,
    DELIMITER ','
);

create table cities (
	CityID INT, 
	CityName VARCHAR(45),
	ZipCode DECIMAL(5,0), 
	CountryID INT, 
	constraint PK_CITIES primary key (CityID), 
	constraint FK_CITIES_COUNTRY foreign key (countryID) references countries(CountryID)
);
copy cities
from 'D:/DOCUMENTS/PROJECT_1/Dataset/cities.csv'
WITH (
    FORMAT csv,
    HEADER true,
    DELIMITER ','
);

CREATE TABLE customers (
    CustomerID INT,
    FirstName VARCHAR(45),
    MiddleInitial VARCHAR(4),
    LastName VARCHAR(45),
    CityID INT,
    Address VARCHAR(90),
    CONSTRAINT PK_CUSTOMERS PRIMARY KEY (CustomerID),
    CONSTRAINT FK_CUSTOMERS_CITIES FOREIGN KEY (CityID) REFERENCES cities(CityID)
);
COPY customers
FROM 'D:/DOCUMENTS/PROJECT_1/Dataset/customers.csv'
WITH (
    FORMAT csv,
    HEADER true,
    DELIMITER ','
);

CREATE TABLE employees (
    EmployeeID INT,
    FirstName VARCHAR(45),
    MiddleInitial VARCHAR(1),
    LastName VARCHAR(45),
    BirthDate DATE,
    Gender VARCHAR(10),
    CityID INT,
    HireDate DATE,
    CONSTRAINT PK_EMPLOYEES PRIMARY KEY (EmployeeID),
    CONSTRAINT FK_EMPLOYEES_CITIES FOREIGN KEY (CityID) REFERENCES cities(CityID)
);

COPY employees
FROM 'D:/DOCUMENTS/PROJECT_1/Dataset/employees.csv' 
WITH (
    FORMAT csv,
    HEADER true,
    DELIMITER ','
);

CREATE TABLE products (
    ProductID INT,
    ProductName VARCHAR(45),
    Price DECIMAL(10,4),
    CategoryID INT,
    Class VARCHAR(15),
    ModifyDate DATE,
    Resistant VARCHAR(15),
    IsAllergic VARCHAR(10), 
    VitalityDays DECIMAL(3,0),
    CONSTRAINT PK_PRODUCTS PRIMARY KEY (ProductID),
    CONSTRAINT FK_PRODUCTS_CATEGORIES FOREIGN KEY (CategoryID) REFERENCES categories(CategoryID)
);

COPY products
FROM 'D:/DOCUMENTS/PROJECT_1/Dataset/products.csv' -- Kiểm tra lại đường dẫn file trên máy bạn
WITH (
    FORMAT csv,
    HEADER true,
    DELIMITER ','
);

-- Tạo bảng sales
CREATE TABLE sales (
    SaleID INT,
    SalesPersonID INT,
    CustomerID INT,
    ProductID INT,
    Quantity INT,
    Discount DECIMAL(10,2),
    TotalPrice DECIMAL(10,2),
    SalesDate DATE,
    TransactionNumber VARCHAR(25),
    CONSTRAINT PK_SALES PRIMARY KEY (SaleID),
	CONSTRAINT FK_SALES_EMPLOYEES FOREIGN KEY (SalesPersonID) REFERENCES employees(EmployeeID),
	CONSTRAINT FK_SALES_CUSTOMERS FOREIGN KEY (CustomerID) REFERENCES customers(CustomerID),
	CONSTRAINT FK_SALES_PRODUCTS FOREIGN KEY (ProductID) REFERENCES products(ProductID)
);

COPY sales
FROM 'D:/DOCUMENTS/PROJECT_1/Dataset/sales.csv'
WITH (
    FORMAT csv,
    HEADER true,
    DELIMITER ','
);
------------------
-- DATA CLEANING
------------------
SELECT 
    COUNT(*) AS tong_so_dong,
    COUNT(SalesDate) AS co_ngay_hop_le,
    COUNT(*) - COUNT(SalesDate) AS bi_null,
    ROUND(
        (COUNT(*) - COUNT(SalesDate))::numeric / COUNT(*) * 100, 
        2
    ) AS pct_bi_null
FROM sales;

-- --> Vì số lượng dòng bị null rất nhỏ (<1%) nên khi xóa sẽ không ảnh hưởng nhiều đến dataset
DELETE FROM sales
WHERE SalesDate IS NULL;

-- Kiểm tra dữ liệu
select * from sales s 
limit 10;
-- --> Toàn bộ cột totalprice đều là giá trị 0 nên phải tính

SELECT MIN(Discount), MAX(Discount), AVG(Discount)
FROM sales;

-- Cập nhật cột totalprice trong bảng sales 
update sales s
set totalprice = p.price * s.quantity * (1 - s.discount )
from products p
where p.productid  = s.productid;


select * from sales s 
where s.totalprice = 0;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_name = 'categories' AND column_name = 'categogyname') THEN
        ALTER TABLE categories RENAME COLUMN categogyname TO categoryname;
    END IF;
END $$;

-- 1.1 Index để các phép JOIN / GROUP BY trên 6.7 triệu dòng chạy nhanh
CREATE INDEX IF NOT EXISTS idx_sales_productid  ON sales (ProductID);
CREATE INDEX IF NOT EXISTS idx_sales_customerid ON sales (CustomerID);
CREATE INDEX IF NOT EXISTS idx_sales_salesperson ON sales (SalesPersonID);
CREATE INDEX IF NOT EXISTS idx_sales_salesdate  ON sales (SalesDate);
CREATE INDEX IF NOT EXISTS idx_customers_city   ON customers (CityID);

--------------------------------------------------------------
-- TÌNH HUỐNG 1: HIỆU SUẤT DOANH THU THEO DÒNG THỜI GIAN
--------------------------------------------------------------

-- 1.1a Tổng doanh thu toàn kỳ
SELECT  ROUND(SUM(s.TotalPrice), 2)                                         AS tong_doanh_thu_thuc_te,
        ROUND(SUM(s.Quantity * p.Price), 2)                                 AS doanh_thu_truoc_chiet_khau,
        ROUND(SUM(s.Quantity * p.Price) - SUM(s.TotalPrice), 2)             AS tong_chiet_khau,
        ROUND(100 * (SUM(s.Quantity * p.Price) - SUM(s.TotalPrice))
                  / NULLIF(SUM(s.Quantity * p.Price), 0), 2)                AS ty_le_chiet_khau_pct,
        SUM(s.Quantity)                                                     AS tong_so_luong,
        COUNT(*)                                                            AS so_dong_hang
FROM    sales s
JOIN    products p ON p.ProductID = s.ProductID;


-- 1.1b Doanh thu theo tháng + tăng trưởng so với tháng trước (MoM) + lũy kế
--      Kèm doanh thu bình quân ngày để so sánh công bằng khi tháng chưa đủ ngày
WITH monthly AS (
    SELECT  DATE_TRUNC('month', SalesDate)::date                      AS sales_month,
            SUM(TotalPrice)                                           AS revenue,
            COUNT(DISTINCT SalesDate::date)                           AS days_with_sales,
            EXTRACT(DAY FROM (DATE_TRUNC('month', MIN(SalesDate))
                              + INTERVAL '1 month - 1 day'))::int     AS days_in_month
    FROM    sales
    WHERE   SalesDate IS NOT NULL
    GROUP BY 1
),
monthly_daily AS (
    SELECT  sales_month, revenue, days_with_sales,
            days_with_sales >= 0.9 * days_in_month   AS is_full_month,
            revenue / days_with_sales                AS revenue_per_day
    FROM    monthly
)
SELECT  sales_month,
        ROUND(revenue, 2)                                                   AS doanh_thu,
        ROUND(100 * (revenue - LAG(revenue) OVER w)
                  / NULLIF(LAG(revenue) OVER w, 0), 2)                      AS mom_doanh_thu_pct,
        ROUND(SUM(revenue) OVER (ORDER BY sales_month), 2)                  AS doanh_thu_luy_ke,
        days_with_sales,
        is_full_month,
        ROUND(revenue_per_day, 2)                                           AS doanh_thu_binh_quan_ngay,
        ROUND(100 * (revenue_per_day - LAG(revenue_per_day) OVER w)
                  / NULLIF(LAG(revenue_per_day) OVER w, 0), 2)              AS mom_binh_quan_ngay_pct
FROM    monthly_daily
WINDOW  w AS (ORDER BY sales_month)
ORDER BY sales_month;


-- Nhiệm vụ 1.2: Biến động và tỷ trọng đóng góp doanh thu của từng danh mục theo tháng
--1.2a Chi tiết: doanh thu, tỷ trọng, hạng trong tháng, thay đổi tỷ trọng (điểm %) và MoM
WITH cat_month AS (
    SELECT  DATE_TRUNC('month', s.SalesDate)::date AS sales_month,
            c.CategoryName,
            SUM(s.TotalPrice)                      AS revenue
    FROM    sales s
    JOIN    products   p ON p.ProductID  = s.ProductID
    JOIN    categories c ON c.CategoryID = p.CategoryID
    WHERE   s.SalesDate IS NOT NULL
    GROUP BY 1, c.CategoryName
),
share AS (
    SELECT  sales_month, CategoryName, revenue,
            100.0 * revenue / SUM(revenue) OVER (PARTITION BY sales_month) AS share_pct
    FROM    cat_month
)
SELECT  sales_month,
        CategoryName,
        ROUND(revenue, 2)                                                   AS doanh_thu,
        ROUND(share_pct, 2)                                                 AS ty_trong_pct,
        RANK() OVER (PARTITION BY sales_month ORDER BY revenue DESC)        AS hang_trong_thang,
        ROUND(share_pct - LAG(share_pct) OVER w, 2)                         AS doi_ty_trong_diem_pct,
        ROUND(100 * (revenue - LAG(revenue) OVER w)
                  / NULLIF(LAG(revenue) OVER w, 0), 2)                      AS mom_doanh_thu_pct
FROM    share
WINDOW  w AS (PARTITION BY CategoryName ORDER BY sales_month)
ORDER BY sales_month, hang_trong_thang;


-- 1.2b Tóm tắt độ ổn định của tỷ trọng: danh mục nào biến động nhiều nhất?
WITH cat_month AS (
    SELECT  DATE_TRUNC('month', s.SalesDate)::date AS sales_month,
            c.CategoryName,
            SUM(s.TotalPrice)                      AS revenue
    FROM    sales s
    JOIN    products   p ON p.ProductID  = s.ProductID
    JOIN    categories c ON c.CategoryID = p.CategoryID
    WHERE   s.SalesDate IS NOT NULL
    GROUP BY 1, c.CategoryName
),
share AS (
    SELECT  sales_month, CategoryName,
            100.0 * revenue / SUM(revenue) OVER (PARTITION BY sales_month) AS share_pct
    FROM    cat_month
)
SELECT  CategoryName,
        ROUND(AVG(share_pct), 2)         AS ty_trong_trung_binh_pct,
        ROUND(MIN(share_pct), 2)         AS ty_trong_thap_nhat_pct,
        ROUND(MAX(share_pct), 2)         AS ty_trong_cao_nhat_pct,
        ROUND(MAX(share_pct) - MIN(share_pct), 2) AS bien_do_diem_pct,
        ROUND(STDDEV_SAMP(share_pct), 2) AS do_lech_chuan
FROM    share
GROUP BY CategoryName
ORDER BY ty_trong_trung_binh_pct DESC;

--------------------------------------------------------------
-- TÌNH HUỐNG 2: ĐỊNH BIÊN VÀ PHÂN LOẠI SẢN PHẨM KINH DOANH 
--------------------------------------------------------------
-- Nhiệm vụ 2.1: Xếp hạng theo doanh thu tích lũy; Top 5 bán chạy, Top 5 kém hiệu quả

-- 2.1a Xếp hạng toàn bộ DANH MỤC
SELECT  RANK() OVER (ORDER BY SUM(s.TotalPrice) DESC)                       AS hang,
        c.CategoryName,
        ROUND(SUM(s.TotalPrice), 2)                                         AS doanh_thu,
        SUM(s.Quantity)                                                     AS so_luong,
        ROUND(100 * SUM(s.TotalPrice) / SUM(SUM(s.TotalPrice)) OVER (), 2)  AS ty_trong_pct,
        ROUND(100 * SUM(SUM(s.TotalPrice)) OVER (ORDER BY SUM(s.TotalPrice) DESC) / SUM(SUM(s.TotalPrice)) OVER (), 2)  AS ty_trong_luy_ke_pct
FROM    sales s
JOIN    products   p ON p.ProductID  = s.ProductID
JOIN    categories c ON c.CategoryID = p.CategoryID
GROUP BY c.categoryname
ORDER BY hang;

-- 2.1b Top 5 bán chạy nhất và Top 5 kém hiệu quả nhất (theo SẢN PHẨM)
WITH product_perf AS (
    SELECT  p.ProductID, p.ProductName, c.CategoryName, p.Class,
            COALESCE(SUM(s.Quantity), 0)   AS units,
            COALESCE(SUM(s.TotalPrice), 0) AS revenue
    FROM    products p
    JOIN    categories c ON c.CategoryID = p.CategoryID
    LEFT JOIN sales s    ON s.ProductID  = p.ProductID
    GROUP BY p.ProductID, p.ProductName, c.CategoryName, p.Class
),
ranked AS (
    SELECT  v.*,
            RANK()       OVER (ORDER BY revenue DESC)              AS hang_doanh_thu,
            ROW_NUMBER() OVER (ORDER BY revenue DESC, ProductID)   AS rn_top,
            ROW_NUMBER() OVER (ORDER BY revenue ASC,  ProductID)   AS rn_bottom
    FROM    product_perf v
)
SELECT  1 AS thu_tu, 'TOP 5 bán chạy' AS nhom, hang_doanh_thu, ProductID, ProductName, CategoryName,
        units, ROUND(revenue, 2) AS doanh_thu
FROM    ranked WHERE rn_top <= 5
UNION ALL
SELECT  2, 'BOTTOM 5 kém hiệu quả', hang_doanh_thu, ProductID, ProductName, CategoryName,
        units, ROUND(revenue, 2)
FROM    ranked WHERE rn_bottom <= 5
ORDER BY thu_tu, hang_doanh_thu;

-- 2.1c Bảng xếp hạng đầy đủ toàn bộ sản phẩm (để đưa vào báo cáo / Power BI)
WITH product_perf AS (
    SELECT  p.ProductID, p.ProductName, c.CategoryName, p.Class,
            COALESCE(SUM(s.Quantity), 0)   AS units,
            COALESCE(SUM(s.TotalPrice), 0) AS revenue
    FROM    products p
    JOIN    categories c ON c.CategoryID = p.CategoryID
    LEFT JOIN sales s    ON s.ProductID  = p.ProductID
    GROUP BY p.ProductID, p.ProductName, c.CategoryName, p.Class
)
SELECT  RANK() OVER (ORDER BY revenue DESC) AS hang_doanh_thu,
        ProductID, ProductName, CategoryName, Class, units, ROUND(revenue, 2) AS doanh_thu
FROM    product_perf
ORDER BY hang_doanh_thu;

-- Nhiệm vụ 2.2: Tương quan giữa số lượng bán và doanh thu; tìm sản phẩm biên thấp nhưng nhu cầu cực cao
-- 2.2a Hệ số tương quan Pearson toàn hệ thống (mức sản phẩm)
WITH product_perf AS (
    SELECT  p.ProductID,
            COALESCE(SUM(s.Quantity), 0)   AS units,
            COALESCE(SUM(s.TotalPrice), 0) AS revenue
    FROM    products p
    LEFT JOIN sales s ON s.ProductID = p.ProductID
    GROUP BY p.ProductID
)
SELECT  COUNT(*)                                                AS so_san_pham,
        ROUND(CORR(units, revenue)::numeric, 4)                 AS corr_so_luong_doanh_thu,
        ROUND(CORR(units, net_price)::numeric, 4)               AS corr_so_luong_don_gia
FROM   (SELECT units, revenue, revenue / NULLIF(units, 0) AS net_price
        FROM   product_perf WHERE units > 0) t;
-- corr_so_luong_don_gia âm => sản phẩm rẻ có xu hướng bán nhiều đơn vị hơn.

-- 2.2b Tương quan theo từng danh mục
WITH product_perf AS (
    SELECT  p.ProductID, c.CategoryName,
            COALESCE(SUM(s.Quantity), 0)   AS units,
            COALESCE(SUM(s.TotalPrice), 0) AS revenue
    FROM    products p
    JOIN    categories c ON c.CategoryID = p.CategoryID
    LEFT JOIN sales s    ON s.ProductID  = p.ProductID
    GROUP BY p.ProductID, c.CategoryName
)
SELECT  CategoryName,
        COUNT(*)                                               AS so_san_pham,
        ROUND(CORR(units, revenue)::numeric, 4)                AS corr_so_luong_doanh_thu
FROM    product_perf
WHERE   units > 0
GROUP BY CategoryName
ORDER BY corr_so_luong_doanh_thu;

-- 2.2c Sản phẩm bán rất nhiều (top 20% số lượng) nhưng đơn giá thực thu rất thấp (bottom 20%)
WITH product_perf AS (
    SELECT  p.ProductID, p.ProductName, c.CategoryName, p.Class,
            COALESCE(SUM(s.Quantity), 0)           AS units,
            COALESCE(SUM(s.TotalPrice), 0)         AS revenue,
            COALESCE(SUM(s.Quantity * p.Price), 0) AS gross_revenue
    FROM    products p
    JOIN    categories c ON c.CategoryID = p.CategoryID
    LEFT JOIN sales s    ON s.ProductID  = p.ProductID
    GROUP BY p.ProductID, p.ProductName, c.CategoryName, p.Class
),
base AS (
    SELECT  v.*,
            revenue / NULLIF(units, 0)                         AS net_price_per_unit,
            100 * (1 - revenue / NULLIF(gross_revenue, 0))     AS effective_discount_pct
    FROM    product_perf v
    WHERE   units > 0
),
scored AS (
    SELECT  b.*,
            PERCENT_RANK() OVER (ORDER BY units)               AS pr_units,
            PERCENT_RANK() OVER (ORDER BY net_price_per_unit)  AS pr_price
    FROM    base b
)
SELECT  ProductID, ProductName, CategoryName, Class,
        units,
        ROUND(revenue, 2)                AS doanh_thu,
        ROUND(net_price_per_unit, 2)     AS don_gia_thuc_thu,
        ROUND(effective_discount_pct, 2) AS chiet_khau_thuc_te_pct,
        ROUND(pr_units::numeric, 2)      AS phan_vi_so_luong,
        ROUND(pr_price::numeric, 2)      AS phan_vi_don_gia
FROM    scored
WHERE   pr_units >= 0.8 AND pr_price <= 0.2
ORDER BY units DESC;

-- 2.2d Phân loại toàn bộ sản phẩm thành 4 nhóm theo (nhu cầu, đơn giá)
WITH product_perf AS (
    SELECT  p.ProductID,
            COALESCE(SUM(s.Quantity), 0)   AS units,
            COALESCE(SUM(s.TotalPrice), 0) AS revenue
    FROM    products p
    LEFT JOIN sales s ON s.ProductID = p.ProductID
    GROUP BY p.ProductID
),
base AS (
    SELECT  ProductID, units, revenue / NULLIF(units, 0) AS net_price
    FROM    product_perf WHERE units > 0
),
med AS (
    SELECT  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY units)     AS med_units,
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY net_price) AS med_price
    FROM    base
)
SELECT  CASE WHEN b.units >= m.med_units AND b.net_price <  m.med_price THEN '1. Nhu cầu cao - giá thấp (biên thấp)'
             WHEN b.units >= m.med_units AND b.net_price >= m.med_price THEN '2. Nhu cầu cao - giá cao (sản phẩm ngôi sao)'
             WHEN b.units <  m.med_units AND b.net_price >= m.med_price THEN '3. Nhu cầu thấp - giá cao (ngách)'
             ELSE '4. Nhu cầu thấp - giá thấp (cân nhắc loại bỏ)' END AS nhom,
        COUNT(*)                         AS so_san_pham,
        SUM(b.units)                     AS tong_so_luong,
        ROUND(SUM(b.units * b.net_price), 2) AS tong_doanh_thu
FROM    base b CROSS JOIN med m
GROUP BY 1
ORDER BY 1;

--------------------------------------------------------------
-- TÌNH HUỐNG 3: HÀNH VI VÀ CHÂN DUNG KHÁCH HÀNG
--------------------------------------------------------------

-- Nhiệm vụ 3.1: Phân khúc khách hàng theo 2 chỉ số: TẦN SUẤT (số đơn) và GIÁ TRỊ (tổng chi tiêu)
-- 3.1a Ngưỡng phân khúc
WITH orders AS (
    SELECT  TransactionNumber, CustomerID, SUM(TotalPrice) AS order_value
    FROM    sales
    GROUP BY TransactionNumber, CustomerID
),
cust AS (
    SELECT  CustomerID, COUNT(*) AS orders, SUM(order_value) AS total_spent
    FROM    orders
    GROUP BY CustomerID
)
SELECT  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY orders)::numeric(10,2)       AS trung_vi_so_don,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_spent)::numeric(14,2)  AS trung_vi_chi_tieu
FROM    cust;

-- 3.1b Kết quả phân khúc
WITH orders AS (
    SELECT  TransactionNumber, CustomerID, SUM(TotalPrice) AS order_value
    FROM    sales
    GROUP BY TransactionNumber, CustomerID
),
cust AS (
    SELECT  CustomerID, COUNT(*) AS orders, SUM(order_value) AS total_spent
    FROM    orders
    GROUP BY CustomerID
),
thresholds AS (
    SELECT  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY orders)      AS med_f,
            PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_spent) AS med_m
    FROM    cust
),
seg AS (
    SELECT  cs.*,
            CASE WHEN cs.orders >= t.med_f AND cs.total_spent >= t.med_m THEN '1. VIP (mua nhiều, chi nhiều)'
                 WHEN cs.orders >= t.med_f                              THEN '2. Thân thiết (mua nhiều, chi vừa)'
                 WHEN cs.total_spent >= t.med_m                         THEN '3. Chi lớn (mua ít lần, chi nhiều)'
                 ELSE '4. Giá trị thấp (mua ít, chi ít)' END AS segment
    FROM    cust cs CROSS JOIN thresholds t
)
SELECT  segment,
        COUNT(*)                                                   AS so_khach_hang,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)         AS ty_le_khach_pct,
        ROUND(SUM(total_spent), 2)                                 AS doanh_thu,
        ROUND(100 * SUM(total_spent) / SUM(SUM(total_spent)) OVER (), 2) AS ty_trong_doanh_thu_pct,
        ROUND(AVG(orders), 2)                                      AS so_don_tb,
        ROUND(AVG(total_spent), 2)                                 AS chi_tieu_tb
FROM    seg
GROUP BY segment
ORDER BY segment;

-- 3.1c Danh sách 20 khách hàng giá trị nhất (để marketing chăm sóc)
WITH orders AS (
    SELECT  TransactionNumber, CustomerID, SUM(TotalPrice) AS order_value
    FROM    sales
    GROUP BY TransactionNumber, CustomerID
),
cust AS (
    SELECT  CustomerID, COUNT(*) AS orders, SUM(order_value) AS total_spent
    FROM    orders
    GROUP BY CustomerID
)
SELECT  cs.CustomerID, cu.FirstName, cu.LastName, ci.CityName,
        cs.orders, ROUND(cs.total_spent, 2) AS tong_chi_tieu
FROM    cust cs
JOIN    customers cu ON cu.CustomerID = cs.CustomerID
JOIN    cities    ci ON ci.CityID     = cu.CityID
ORDER BY cs.total_spent DESC
LIMIT 20;

-- Nhiệm vụ 3.2: Tỷ lệ khách hàng quay lại (Repeat) và khách chỉ mua một lần (One-time)
WITH orders AS (
    SELECT  TransactionNumber, CustomerID, SUM(TotalPrice) AS order_value
    FROM    sales
    GROUP BY TransactionNumber, CustomerID
),
cust AS (
    SELECT  CustomerID, COUNT(*) AS orders, SUM(order_value) AS total_spent
    FROM    orders
    GROUP BY CustomerID
)
SELECT  CASE WHEN orders >= 2 THEN 'Repeat Customers (>= 2 đơn)'
             ELSE 'One-time Buyers (1 đơn)' END                     AS nhom,
        COUNT(*)                                                    AS so_khach_hang,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)          AS ty_le_khach_pct,
        ROUND(SUM(total_spent), 2)                                  AS doanh_thu,
        ROUND(100 * SUM(total_spent) / SUM(SUM(total_spent)) OVER (), 2) AS ty_trong_doanh_thu_pct,
        ROUND(AVG(total_spent), 2)                                  AS chi_tieu_tb_moi_khach,
        ROUND(AVG(orders), 2)                                       AS so_don_tb
FROM    cust
GROUP BY 1
ORDER BY 1 DESC;

-- Nhiệm vụ 3.3: Giá trị đơn hàng trung bình (AOV) và quy mô giỏ hàng (Basket Size)
-- 3.3a Toàn hệ thống
WITH orders AS (
    SELECT  TransactionNumber, CustomerID,
            COUNT(*) AS line_items, SUM(Quantity) AS units, SUM(TotalPrice) AS order_value
    FROM    sales
    GROUP BY TransactionNumber, CustomerID
)
SELECT  COUNT(*)                                                    AS so_don_hang,
        ROUND(SUM(order_value) / COUNT(*), 2)                       AS aov,
        ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY order_value)::numeric, 2) AS aov_trung_vi,
        ROUND(AVG(line_items), 2)                                   AS basket_size_dong_hang_tb,
        ROUND(AVG(units), 2)                                        AS basket_size_don_vi_tb
FROM    orders;

-- 3.3b AOV và Basket Size theo tháng
WITH orders AS (
    SELECT  TransactionNumber, CustomerID, MIN(SalesDate) AS order_date,
            COUNT(*) AS line_items, SUM(Quantity) AS units, SUM(TotalPrice) AS order_value
    FROM    sales
    GROUP BY TransactionNumber, CustomerID
)
SELECT  DATE_TRUNC('month', order_date)::date                       AS thang,
        COUNT(*)                                                    AS so_don_hang,
        ROUND(SUM(order_value) / COUNT(*), 2)                       AS aov,
        ROUND(AVG(line_items), 2)                                   AS basket_size_dong_hang_tb,
        ROUND(AVG(units), 2)                                        AS basket_size_don_vi_tb
FROM    orders
WHERE   order_date IS NOT NULL
GROUP BY 1
ORDER BY 1;

-- 3.3c Phân bố quy mô giỏ hàng (số dòng hàng / đơn)
WITH orders AS (
    SELECT  TransactionNumber, CustomerID, COUNT(*) AS line_items
    FROM    sales
    GROUP BY TransactionNumber, CustomerID
)
SELECT  line_items                                                  AS so_dong_hang_trong_don,
        COUNT(*)                                                    AS so_don,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)          AS ty_le_pct
FROM    orders
GROUP BY line_items
ORDER BY line_items;


