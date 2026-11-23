
-- Task 1. Create a view
/*
Create a view called 'sales_revenue_by_category_qtr' that shows 
the film category and total sales revenue for the current quarter and year. 
The view should only display categories with at least one sale in the current quarter.

Note: make it dynamic - when the next quarter begins, it automatically 
considers that as the current quarter.

Explanations:
- Why this logic is used & how the result is calculated:
  I join payment -> rental -> inventory -> film -> film_category -> category using INNER JOINs 
  to associate every payment with its corresponding film category, filter by the current year and quarter, 
  and calculate total revenue using SUM(p.amount) grouped by category.
- Current quarter:
  Extracted dynamically at query execution time using EXTRACT(QUARTER FROM CURRENT_DATE) and matched against payment_date.
- Current year:
  Extracted dynamically using EXTRACT(YEAR FROM CURRENT_DATE) and matched against payment_date.
- Why only categories with sales appear:
  INNER JOIN requires matching records across all tables down to payment, so only categories with recorded payments are included.
- How zero-sales categories are excluded:
  Categories without payments in the current quarter/year have no matching rows in payment after the WHERE filter and are excluded before grouping.
- Why the current default database returns no data & how it was verified:
  The default dvdrental database only contains payment data from 2007 (Q1 and Q2), so querying for 2026 returns 0 rows. 
  The logic was verified by temporarily substituting CURRENT_DATE in the SELECT query with a historical date from payment.payment_date (e.g., '2007-02-15').
- Example of data that should NOT appear:
  Any payment from a different year or quarter (e.g., all existing 2007 payments in dvdrental when querying in 2026, or Q1 2007 payments when querying Q2 2007), 
  as well as any film category that has 0 payments during the target quarter.
*/

CREATE OR REPLACE VIEW public.sales_revenue_by_category_qtr AS
SELECT 
    c."name" AS category_name,
    SUM(p.amount) AS total_sales_revenue
FROM public.payment p
INNER JOIN public.rental r ON p.rental_id = r.rental_id
INNER JOIN public.inventory i ON r.inventory_id = i.inventory_id
INNER JOIN public.film f ON i.film_id = f.film_id
INNER JOIN public.film_category fc ON f.film_id = fc.film_id
INNER JOIN public.category c ON fc.category_id = c.category_id 
WHERE EXTRACT(YEAR FROM CURRENT_DATE) = EXTRACT(YEAR FROM p.payment_date)
  AND EXTRACT(QUARTER FROM CURRENT_DATE) = EXTRACT(QUARTER FROM p.payment_date)
GROUP BY c.category_id, c."name";

-- Test queries for Task 1:
-- Valid query (returns 0 rows because dvdrental has no payments in 2026):
SELECT * FROM public.sales_revenue_by_category_qtr;
-- Filtered query on the view (edge case check - returns 0 rows):
SELECT * FROM public.sales_revenue_by_category_qtr WHERE category_name = 'Action';


-- Task 2. Create a query language function
/*
Create a query language function called 'get_sales_revenue_by_category_qtr' 
that accepts one parameter representing the current quarter and year 
and returns the same result as the 'sales_revenue_by_category_qtr' view.

Explanations:
- Why this logic is used & how the result is calculated:
  Uses pure SQL (LANGUAGE SQL) with the same INNER JOIN chain and SUM(p.amount) aggregation as Task 1, 
  but replaces CURRENT_DATE with an input parameter (defaulting to CURRENT_DATE) to make the function reusable for any period.
- Why parameter is needed:
  Unlike the static view which only evaluates CURRENT_DATE, a parameter allows querying historical or specific quarters/years (such as 2017 in dvdrental).
  A DATE parameter (with DEFAULT CURRENT_DATE) is used because PostgreSQL has no native year-quarter type, and a DATE encapsulates both year and quarter.
- What happens if an invalid quarter/input is passed:
  Because language SQL does not support procedural RAISE EXCEPTION blocks, PostgreSQL's built-in DATE type parser validates the input automatically 
  and immediately aborts execution with a "date/time field value out of range" error if an invalid date/month is supplied.
- What happens if no data exists / required data is missing:
  For a valid date with no matching payments in the database (or NULL input), the function executes cleanly without errors and returns an empty result set (0 rows).
*/

CREATE OR REPLACE FUNCTION public.get_sales_revenue_by_category_qtr(curr_qtr_yr DATE DEFAULT CURRENT_DATE)
RETURNS TABLE (
    category_name TEXT,
    total_sales_revenue NUMERIC
)
LANGUAGE SQL
AS $$
    SELECT 
        c."name"::TEXT AS category_name,
        SUM(p.amount) AS total_sales_revenue
    FROM public.payment p
    INNER JOIN public.rental r ON p.rental_id = r.rental_id
    INNER JOIN public.inventory i ON r.inventory_id = i.inventory_id
    INNER JOIN public.film f ON i.film_id = f.film_id
    INNER JOIN public.film_category fc ON f.film_id = fc.film_id
    INNER JOIN public.category c ON fc.category_id = c.category_id 
    WHERE EXTRACT(YEAR FROM curr_qtr_yr) = EXTRACT(YEAR FROM p.payment_date)
      AND EXTRACT(QUARTER FROM curr_qtr_yr) = EXTRACT(QUARTER FROM p.payment_date)
    GROUP BY c.category_id, c."name";
$$;

-- Test queries for Task 2:
-- 1. Valid input (historical date with existing data in dvdrental - Q1 2017):
SELECT * FROM public.get_sales_revenue_by_category_qtr('2017-02-15');
-- 2. Valid input using optional default parameter (CURRENT_DATE - returns 0 rows):
SELECT * FROM public.get_sales_revenue_by_category_qtr();
-- 3. Edge/Invalid input (commented out so the script runs cleanly):
-- SELECT * FROM public.get_sales_revenue_by_category_qtr('2017-02-30'); -- Throws ERROR: date/time field value out of range


-- Task 3. Create procedure language function
/*
Create a function that takes a country as an input parameter and returns 
the most popular film in that specific country.

Explanations:
- Why this logic is used & how the result is calculated:
  Joins country -> city -> address -> customer -> rental -> inventory -> film -> language via INNER JOINs 
  to count rentals per film specifically for customers residing in the requested countries (rather than store locations).
  Uses DISTINCT ON (cfr.country) ordered by rental_count DESC to pick the single top film per country.
- How 'most popular' is defined:
  Defined by the highest total number of rentals (COUNT(r.rental_id)) in that specific country, reflecting actual customer demand.
- How ties are handled:
  If two or more films have the exact same maximum rental count in a country, the tie is broken deterministically 
  by sorting film titles alphabetically (cfr.title ASC), returning the first title in alphabetical order.
- What happens if country has no data:
  If a country in the input array does not exist in the database or has zero rentals, INNER JOIN produces no rows for it, 
  and that country is simply omitted from the returned table without throwing an error.
- What happens if input parameters are incorrect:
  An explicit IF check with RAISE EXCEPTION validates the input array. If NULL or an empty array is passed, 
  execution stops immediately with a descriptive error message.
*/

CREATE OR REPLACE FUNCTION public.most_popular_films_by_countries(
    targeted_countries TEXT[] DEFAULT ARRAY['United States']
)
RETURNS TABLE (
    country TEXT,
    film TEXT,
    rating TEXT,
    language TEXT,
    length SMALLINT,
    release_year INTEGER
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF targeted_countries IS NULL OR array_length(targeted_countries, 1) IS NULL THEN
        RAISE EXCEPTION 'Input array of countries cannot be NULL or empty.';
    END IF;
    
    RETURN QUERY
    WITH country_film_rentals AS (
        SELECT 
            cntr.country,
            COUNT(r.rental_id) AS rental_count,
            f.film_id, 
            f.title, 
            f.rating,
            l."name" AS language,
            f.length, 
            f.release_year
        FROM public.country cntr
        INNER JOIN public.city cty ON cntr.country_id = cty.country_id 
        INNER JOIN public.address addr ON cty.city_id = addr.city_id 
        INNER JOIN public.customer cst ON addr.address_id = cst.address_id  
        INNER JOIN public.rental r ON r.customer_id = cst.customer_id 
        INNER JOIN public.inventory i ON r.inventory_id = i.inventory_id  
        INNER JOIN public.film f ON i.film_id = f.film_id
        INNER JOIN public."language" l ON f.language_id = l.language_id 
        WHERE cntr.country ILIKE ANY(targeted_countries)
        GROUP BY cntr.country, f.film_id, f.title, f.rating, l."name", f.length, f.release_year
    )
    SELECT DISTINCT ON (cfr.country)
        cfr.country::TEXT,
        cfr.title::TEXT, 
        cfr.rating::TEXT,
        cfr.language::TEXT,
        cfr.length::SMALLINT,
        cfr.release_year::INTEGER
    FROM country_film_rentals cfr
    ORDER BY cfr.country ASC, 
             cfr.rental_count DESC, 
             cfr.title ASC;
END;
$$;

-- Test queries for Task 3:
-- Valid input with multiple countries:
SELECT * FROM public.most_popular_films_by_countries(ARRAY['Afghanistan', 'Brazil', 'United States']);
-- Valid input using optional default parameter ('United States'):
SELECT * FROM public.most_popular_films_by_countries();
-- Edge input (non-existent country returns 0 rows without error):
SELECT * FROM public.most_popular_films_by_countries(ARRAY['Atlantis']);
-- Invalid input (commented out so the script runs cleanly):
-- SELECT * FROM public.most_popular_films_by_countries(ARRAY[]::TEXT[]); -- Triggers RAISE EXCEPTION


-- Task 4. Create procedure language function
/*
Create a function that generates a list of movies available in stock based on 
a partial title match (e.g., movies containing the word 'love' in their title).

Explanations:
- Why this logic is used & how the result is calculated:
  We filter films matching the partial title pattern (using ILIKE) and check physical copies in public.inventory 
  that are currently in stock (i.e., have no active unreturned rental where return_date IS NULL). 
  Using DISTINCT ON (i.inventory_id) ordered by rental_date DESC, we retrieve the most recent rental details 
  (customer name and rental date) for each available copy, then iterate through the sorted results in PL/pgSQL 
  to generate a sequential row_num counter starting at 1 without using window functions.
- How pattern matching works (LIKE, %):
  The LIKE / ILIKE operators match text against a pattern where '%' acts as a wildcard representing zero, 
  one, or multiple arbitrary characters. For example, '%love%' matches any title containing 'love' at the 
  beginning, middle, or end.
- Case sensitivity:
  Standard LIKE is case-sensitive ('%love%' would not match 'LOVE STORY', and all film titles in dvdrental 
  are stored in uppercase). Using PostgreSQL's ILIKE performs case-insensitive pattern matching so '%love%', 
  '%LOVE%', and '%Love%' all return the same matching films.
- How performance is ensured:
  1. Bottleneck on large data: Leading-wildcard patterns ('%love%') prevent PostgreSQL from using a standard 
     B-Tree index on film.title, forcing a Sequential Scan on the film table.
  2. Optimization in this implementation: We apply the title filter first on the relatively small film table 
     before joining inventory, and use a correlated NOT EXISTS anti-join on rental(inventory_id, return_date) 
     which short-circuits as soon as an open rental is found instead of aggregating full rental histories.
- What happens if:
  - Multiple matches: All available inventory copies matching the pattern are returned, sorted alphabetically 
    by film title and rental date, with row_num incrementing sequentially (1, 2, 3, ...).
  - No matches (or required data is missing): If no matching movies are currently in stock, the loop executes 
    0 times (v_counter = 0), and the function returns a single informative row with row_num = 1 and a message 
    in film_title stating that no movie matching the title was found in stock.
  - Input parameters are incorrect: If NULL or an empty/whitespace-only string is passed, an explicit 
    IF check triggers RAISE EXCEPTION and stops execution immediately.
*/

CREATE OR REPLACE FUNCTION public.films_in_stock_by_title(
    p_title TEXT DEFAULT '%love%'
)
RETURNS TABLE (
    row_num INTEGER,
    film_title TEXT,
    language TEXT,
    customer_name TEXT,
    rental_date TIMESTAMP
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_counter INTEGER := 0;
    v_rec RECORD;
BEGIN
    IF p_title IS NULL OR TRIM(p_title) = '' THEN
        RAISE EXCEPTION 'Input title pattern cannot be NULL or empty.';
    END IF;

    FOR v_rec IN (
        WITH available_copies_latest_rental AS (
            SELECT DISTINCT ON (i.inventory_id)
                f.title,
                l."name" AS language_name,
                c.first_name || ' ' || c.last_name AS full_customer_name,
                r.rental_date AS last_rental_date
            FROM public.film f
            INNER JOIN public."language" l ON f.language_id = l.language_id
            INNER JOIN public.inventory i ON f.film_id = i.film_id
            LEFT JOIN public.rental r ON i.inventory_id = r.inventory_id
            LEFT JOIN public.customer c ON r.customer_id = c.customer_id
            WHERE f.title ILIKE p_title
              AND NOT EXISTS (
                  SELECT 1
                  FROM public.rental r_active
                  WHERE r_active.inventory_id = i.inventory_id
                    AND r_active.return_date IS NULL
              )
            ORDER BY i.inventory_id, r.rental_date DESC NULLS LAST
        )
        SELECT
            title,
            language_name,
            full_customer_name,
            last_rental_date
        FROM available_copies_latest_rental
        ORDER BY title ASC, last_rental_date DESC NULLS LAST
    )
    LOOP
        v_counter := v_counter + 1;
        row_num := v_counter;
        film_title := v_rec.title::TEXT;
        language := v_rec.language_name::TEXT;
        customer_name := v_rec.full_customer_name::TEXT;
        rental_date := v_rec.last_rental_date::TIMESTAMP;
        RETURN NEXT;
    END LOOP;

    IF v_counter = 0 THEN
        row_num := 1;
        film_title := 'Movie with title "' || p_title || '" was not found in stock.';
        language := NULL;
        customer_name := NULL;
        rental_date := NULL;
        RETURN NEXT;
    END IF;

    RETURN;
END;
$$;

-- Test queries for Task 4:
-- 1. Valid input (multiple matches in stock, case-insensitive):
SELECT * FROM public.films_in_stock_by_title('%love%');
-- 2. Valid input using optional default parameter ('%love%'):
SELECT * FROM public.films_in_stock_by_title();
-- 3. Edge input (valid pattern with no matching films in stock - returns "not found" message row):
SELECT * FROM public.films_in_stock_by_title('%nonexistentmovie123%');
-- 4. Invalid input (commented out so the script runs cleanly without aborting):
-- SELECT * FROM public.films_in_stock_by_title(''); -- Triggers RAISE EXCEPTION



-- Task 5. Create procedure language function
/*
Create a procedure language function called 'new_movie' that takes a movie title 
as a parameter and inserts a new movie with the given title in the film table. 
The function should generate a new unique film ID, set the rental rate to 4.99, 
the rental duration to three days, the replacement cost to 19.99. The release year 
and language are optional and by default should be current year and Klingon respectively. 
The function should also verify that the language exists in the 'language' table. 
The function must prevent inserting duplicate movie titles and raise an exception if duplicate exists.
Ensure that no such function has been created before; if so, replace it.

Explanations:
- Why this logic is used & how the result is calculated:
  Uses PL/pgSQL to validate inputs, resolve the foreign key language_id dynamically from public.language, 
  prevent duplicate titles, and atomically insert a new record into public.film while returning the 
  newly generated film_id (or movie details) so the caller can confirm the insertion.
- How unique ID is generated:
  We find the current highest film_id in public.film using COALESCE(MAX(film_id), 0) + 1 
  and store it in v_new_film_id before inserting, ensuring a new unique ID without hardcoding values.
- How no duplicates are ensured:
  Before inserting, we check public.film using EXISTS (SELECT 1 FROM public.film WHERE LOWER(TRIM(title)) = LOWER(TRIM(p_title))) 
  for a case-insensitive and whitespace-trimmed match against existing movie titles.
- What happens if movie already exists:
  If a duplicate title is found, the function immediately executes RAISE EXCEPTION with a descriptive message, 
  halting execution and preventing the INSERT from running.
- How language existence is validated:
  We query public.language using TRIM(UPPER(name)) = TRIM(UPPER(p_language)) (TRIM is critical because language.name 
  in dvdrental is CHAR(20), which pads strings with trailing spaces) into v_language_id. If NOT FOUND (v_language_id IS NULL), 
  RAISE EXCEPTION is triggered. (Note: 'Klingon' does not exist in default dvdrental unless added beforehand, so calling 
  with default language will raise an exception unless 'Klingon' is inserted into public.language first).
- What happens if insertion fails & how consistency is preserved:
  Every PL/pgSQL function executes within a single implicit transaction block (or subtransaction). If any validation fails 
  (RAISE EXCEPTION) or a database constraint violation occurs during INSERT (such as invalid release_year domain check), 
  PostgreSQL automatically rolls back all changes made inside the function, ensuring atomicity and database consistency 
  with no partial or orphaned records.
*/

CREATE OR REPLACE FUNCTION public.new_movie(
    p_title TEXT,
    p_release_year INTEGER DEFAULT EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER,
    p_language TEXT DEFAULT 'Klingon'
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_language_id SMALLINT;
    v_new_film_id INTEGER;
BEGIN
    -- 1. Validate title input (cannot be NULL or blank)
    IF p_title IS NULL OR TRIM(p_title) = '' THEN
        RAISE EXCEPTION 'Movie title cannot be NULL or empty.';
    END IF;

    -- 2. Validate language input and verify existence in public.language
    IF p_language IS NULL OR TRIM(p_language) = '' THEN
        RAISE EXCEPTION 'Language cannot be NULL or empty.';
    END IF;

    SELECT l.language_id
    INTO v_language_id
    FROM public."language" l
    WHERE TRIM(UPPER(l."name")) = TRIM(UPPER(p_language));

    IF NOT FOUND OR v_language_id IS NULL THEN
        RAISE EXCEPTION 'Language "%" does not exist in the language table.', p_language;
    END IF;

    -- 3. Prevent duplicate movie titles (case-insensitive check)
    IF EXISTS (
        SELECT 1
        FROM public.film f
        WHERE TRIM(UPPER(f.title)) = TRIM(UPPER(p_title))
    ) THEN
        RAISE EXCEPTION 'Duplicate movie title: "%" already exists in the film table.', p_title;
    END IF;

    -- 4. Generate unique film_id from the table sequence and insert the new movie
    SELECT COALESCE(MAX(film_id), 0) + 1
    INTO v_new_film_id
    FROM public.film;

    INSERT INTO public.film (
        film_id,
        title,
        release_year,
        language_id,
        rental_duration,
        rental_rate,
        replacement_cost
    )
    VALUES (
        v_new_film_id,
        TRIM(p_title),
        p_release_year,
        v_language_id,
        3,
        4.99,
        19.99
    );

    RETURN v_new_film_id;
END;
$$;

-- Test queries for Task 5:
-- 1. Valid input (explicit existing language 'English' and custom year):
SELECT public.new_movie('Interstellar: Beyond Time', 2026, 'English');

-- Verify the inserted record:
SELECT film_id, title, release_year, language_id, rental_duration, rental_rate, replacement_cost
FROM public.film
WHERE title = 'Interstellar: Beyond Time';

-- Cleanup test record so the script remains rerunnable without duplicate errors:
DELETE FROM public.film WHERE title = 'Interstellar: Beyond Time';

-- 2. Edge / Invalid inputs (commented out so the script executes cleanly):
-- A) Default language 'Klingon' (raises exception because 'Klingon' is not in default public.language):
-- SELECT public.new_movie('Star Trek: The Klingon Empire');

-- B) Duplicate title check (raises exception because 'ACADEMY DINOSAUR' already exists):
-- SELECT public.new_movie('Academy Dinosaur', 2006, 'English');

-- C) Empty title check (raises exception):
-- SELECT public.new_movie('');
