-- -----------------------PART 1----------------------------------------------------------------------------------
/*1.The marketing team needs a list of animation movies 
 * between 2017 and 2019 to promote family-friendly content 
 * in an upcoming season in stores. 
 * Show all animation movies released during this period 
 * with rate more than 1, sorted alphabetically*/

/*List of assumptions:
 * - i interprit the phrase "between 2017 and 2019" as inclusive so I used a BETWEEN operator
 * - "rate more than one" refers to a numeric rate so I filter the data on the rental_rate column, not the rating one
 * - used an INNER JOIN so that there are no films that don't match the criteria or are uncategorized 
 */

/*SOLUTION USING JOIN - the one I would use in production environment. 
 * It tells the database exactly what to connect without adding extra steps, 
 * making it the most efficient choice for production environments.*/
--ADVANTAGES: Good readability, intuitive syntax.
--DISADVANTAGES: Performance can degrade when joining big tables
SELECT f.title, 
		f.description, 
		f.release_year, 
		f.rental_rate, 
		f.rating 
FROM public.film AS f 
INNER JOIN public.film_category AS fc  ON fc.film_id = f.film_id 
INNER JOIN public.category AS c 		ON c.category_id  = fc.category_id 
WHERE UPPER(c.name) = 'ANIMATION' 
	AND f.release_year BETWEEN 2017 AND 2019 
	AND f.rental_rate > 1
ORDER BY f.title ASC;

--SOLUTION USING CTE
--ADVANTAGES: Exceptional readability, breaks down into modular, reusable steps
--DISADVANTAGES: Unnecessary logic for simple filtering tasks, which can unnecessarily consume memory.
WITH animation_films AS(
	SELECT fc.film_id 
	FROM public.film_category AS fc 
	JOIN public.category AS c ON c.category_id = fc.category_id 
	WHERE UPPER(c.name) = 'ANIMATION'
)
SELECT f.title, 
		f.description, 
		f.release_year, 
		f.rental_rate, 
		f.rating 
FROM public.film AS f
JOIN animation_films AS af ON f.film_id = af.film_id 
WHERE f.release_year BETWEEN 2017 AND 2019 
		AND f.rental_rate > 1
ORDER BY f.title ASC;

--SOLUTION USING SUBQUERIES
--ADVANTAGES: Can be faster if the database filters the inner queries efficiently
--DISADVANTAGES: High logical complexity, nested subqueries like these hurt readability
SELECT f.title, 
		f.description, 
		f.release_year, 
		f.rental_rate, 
		f.rating 
FROM public.film AS f 
WHERE f.release_year BETWEEN 2017 AND 2019 
		AND f.rental_rate > 1
		AND f.film_id IN (
						SELECT fc.film_id 
						FROM public.film_category AS fc 
						WHERE fc.category_id IN (
												SELECT c.category_id  
												FROM public.category AS c
												WHERE UPPER(c.name) = 'ANIMATION'
						)
		)
ORDER BY f.title ASC;



/*2.The finance department requires a report on store 
 * performance to assess profitability and plan resource allocation 
 * for stores after March 2017. Calculate the revenue earned 
 * by each rental store after March 2017 (since April) 
 * (include columns: address and address2 – as one column, revenue)*/

/*List of assumptions:
 * - I assume "revenue" is represented by the sum of the amount column in the payment method.
 * - The paymment is processed by a staff member, therefore, we link the payment to the store through the staff table.
 * - "after March 2017(since April) is implemented here by using "WHERE pay.payment_date >= '2017-04-01'"
 * - we need to join the table address and handle null values on its columns address and address2 using COALESCE to get the store adress
 * - we use INNER JOIN to ensure no unvalid data is processed
 */

--SOLUTION USING JOIN
--ADVANTAGES: It is very readable
--DISADVANTAGES: The database joins all rows from payment before it perfroms the grouping(causes high memory usage)
SELECT TRIM(COALESCE(adr.address, '') || ' ' || COALESCE(adr.address2, '')) AS store_address,
       SUM(pay.amount)                                                      AS total_revenue
FROM public.store str
INNER JOIN public.address   adr ON str.address_id   = adr.address_id
INNER JOIN public.inventory inv ON str.store_id     = inv.store_id
INNER JOIN public.rental    rnt ON inv.inventory_id = rnt.inventory_id
INNER JOIN public.payment   pay ON rnt.rental_id    = pay.rental_id
WHERE pay.payment_date >= '2017-04-01'
GROUP BY str.store_id, 
         adr.address, 
         adr.address2;
/*SOLUTION USING CTE - The best approach for this task that I would use in production 
 * because the payment table is the largest of them all. The staff_revenue CTE 
 * handles the aggregation for this table and joins it already optimized and filtered 
 * to the othrer tables. The CTE approach ensures superior code readability here.*/ 
--ADVANTAGES: It separates the business logic from the formatting logic, readable, and easier to follow the relations and the logical approach to the database. 
--DISADVANTAGES: More code.
WITH store_payments AS (
    SELECT inv.store_id,
           SUM(pay.amount) AS total_store_revenue
    FROM public.payment pay
    INNER JOIN public.rental    rnt ON pay.rental_id    = rnt.rental_id
    INNER JOIN public.inventory inv ON rnt.inventory_id = inv.inventory_id
    WHERE pay.payment_date >= '2017-04-01'
    GROUP BY inv.store_id
)
SELECT TRIM(COALESCE(adr.address, '') || ' ' || COALESCE(adr.address2, '')) AS store_address,
       spm.total_store_revenue                                              AS total_revenue
FROM public.store str
INNER JOIN public.address       adr ON str.address_id = adr.address_id
INNER JOIN store_payments       spm ON str.store_id   = spm.store_id;

--SOLUTION USING SUBQUERIES
--ADVANTAGES: Aggregates the large payment table first before joining the other tables
--DISADVANTAGES: Harder to read.
SELECT TRIM(COALESCE(adr.address, '') || ' ' || COALESCE(adr.address2, '')) AS store_address,
       sub.total_store_revenue                                              AS total_revenue
FROM public.store str
INNER JOIN public.address adr ON str.address_id = adr.address_id
INNER JOIN (
    SELECT inv.store_id, 
           SUM(pay.amount) AS total_store_revenue
    FROM public.payment pay
    INNER JOIN public.rental    rnt ON pay.rental_id    = rnt.rental_id
    INNER JOIN public.inventory inv ON rnt.inventory_id = inv.inventory_id
    WHERE pay.payment_date >= '2017-04-01'
    GROUP BY inv.store_id 
) AS sub ON str.store_id = sub.store_id;



/*3.The marketing department in our stores aims to identify 
 * the most successful actors since 2015 to boost customer interest 
 * in their films. Show top-5 actors by number of movies 
 * (released since 2015) they took part in 
 * (columns: first_name, last_name, number_of_movies, 
 * sorted by number_of_movies in descending order)*/

/*List of assumptions:
 * - I interpreted "Since 2015" as films released in or after 2015 (release_year >= 2015)
 * - number_of_movies is calculated by counting the unique film_id associations for each actor.
 * - The "top 5" requirement is met using the LIMIT 5 clause
 * - I use an INNER JOIN as we only want to count the films that the actor has actually played in.
 * - I group by actor_id, first_name and last_name as actors may have the same exact first and last name(ensuring data aggregation)
 * - The data is ordered by number_of_movies in DESC order
 */
--SOLUTION USING JOIN
--ADVANTAGES: Compact, readable and simple.
--DISADVANTAGES: It joins the actor table before aggregating it which can lead to slightly more memory consumption
SELECT a.first_name, a.last_name, COUNT(f.film_id) as number_of_movies
FROM actor a 
INNER JOIN film_actor fa on fa.actor_id = a.actor_id 
INNER JOIN film f ON f.film_id  = fa.film_id 
WHERE f.release_year >= 2015
GROUP BY a.actor_id 
ORDER BY COUNT(f.film_id) DESC
LIMIT 5;

/*SOLUTION USING CTE - I would use this approach in production because it 
 * separates the mathematical calculation from the logical part. 
 * It pre-aggregates the data before joining it which scales better on massive datasets*/
--ADVANTAGES: The code is highly readable and easy to debug because it filters and counts the films before joining them to the actors table.
--DISADVANTAGES: It is a minor drawback but it adds a few extra lines for an otherwise simple aggregation.
WITH actor_movie_counts AS (
    SELECT fact.actor_id, 
           COUNT(fact.film_id) AS number_of_movies
    FROM public.film_actor fact
    INNER JOIN public.film flm ON fact.film_id = flm.film_id 
    WHERE flm.release_year >= 2015
    GROUP BY fact.actor_id
)
SELECT act.first_name, 
       act.last_name, 
       amc.number_of_movies 
FROM public.actor act 
INNER JOIN actor_movie_counts amc ON act.actor_id = amc.actor_id 
ORDER BY amc.number_of_movies DESC
LIMIT 5;

--SOLUTION USING SUBQUERIES
--ADVANTAGES: Filters the films before joining them to the actor table.
--DISADVANTAGES: The structure makes you read the nested syntax inside-out, making it slightly less intuitive
SELECT act.first_name, 
       act.last_name, 
       amc.number_of_movies 
FROM public.actor act 
INNER JOIN (
    SELECT fact.actor_id, 
           COUNT(fact.film_id) AS number_of_movies
    FROM public.film_actor fact
    INNER JOIN public.film flm ON fact.film_id = flm.film_id 
    WHERE flm.release_year >= 2015
    GROUP BY fact.actor_id
) AS amc ON act.actor_id = amc.actor_id 
ORDER BY amc.number_of_movies DESC
LIMIT 5;



/*4.The marketing team needs to track the production trends of Drama, Travel, and Documentary films to inform 
genre-specific marketing strategies. Show number of Drama, Travel, Documentary per year 
(include columns: release_year, number_of_drama_movies, number_of_travel_movies, number_of_documentary_movies), 
sorted by release year in descending order. 
Dealing with NULL values is encouraged)*/

/*List of assumptions:
 * - the category names are exactly Drama, Travel, and Documentary in the databse
 * - we must group the categories as columns not as rows so we need CASE WHEN
 * - dealing with NULL values is implemented with the COALESCE function, which returns 0 instead of Null values
 * - Standard INNER JOINs are used to map films to categories, filtering out any uncategorized films
 */

/*SOLUTION USING JOIN - I would implement this in production, the database engine 
 * only needs to scan the tables and resolve joins one single time, 
 * the pivoting is handled with conditional aggregation(CASE WHEN). */
--ADVANTAGES: Highly efficient because it scans the joined tables 
--DISADVANTAGES: The SELECT claues becomes repetitive because of the multiple conditions in the CASE WHEN clause.
SELECT f.release_year , 
		COALESCE(SUM(CASE WHEN UPPER(c.name) = 'DRAMA' 	 	THEN 1 ELSE 0 END), 0) as number_of_drama_movies, 
		COALESCE(SUM(CASE WHEN UPPER(c.name) = 'TRAVEL' 	 	THEN 1 ELSE 0 END), 0) as number_of_travel_movies, 
		COALESCE(SUM(CASE WHEN UPPER(c.name) = 'DOCUMENTARY' 	THEN 1 ELSE 0 END), 0) as number_of_documentary_movies
FROM public.film f 
INNER JOIN public.film_category fc 	ON f.film_id = fc.film_id 
INNER JOIN public.category 		c 	ON c.category_id = fc.category_id 
WHERE UPPER(c.name) IN ('DRAMA', 'DOCUMENTARY', 'TRAVEL')
GROUP BY f.release_year
ORDER BY f.release_year DESC;


--SOLUTION USING CTE
--ADVANTAGES: This approach isolates the filtering logic, creating a clean, pre-filtered dataset of the three targeted genres. Makes the main query much easier to read and maintain.
--DISADVANTAGES: It introduces slight structural overhead by splitting a straightforward grouping task into two steps, which is completely unnecessary for a query of this size.
WITH filtered_genres AS (
	SELECT f.release_year,
			c.name AS cat_name
	FROM public.film f 
	INNER JOIN public.film_category fc 	ON f.film_id = fc.film_id 
INNER JOIN public.category 			c 	ON c.category_id = fc.category_id 
	WHERE UPPER(c.name) IN ('DRAMA', 'DOCUMENTARY', 'TRAVEL')
	
)
SELECT fg.release_year , 
		COALESCE(SUM(CASE WHEN UPPER(fg.cat_name) =  'DRAMA' 		THEN 1 ELSE 0 END), 0) as number_of_drama_movies, 
		COALESCE(SUM(CASE WHEN UPPER(fg.cat_name) =  'TRAVEL' 		THEN 1 ELSE 0 END), 0) as number_of_travel_movies, 
		COALESCE(SUM(CASE WHEN UPPER(fg.cat_name) =  'DOCUMENTARY' THEN 1 ELSE 0 END), 0) as number_of_documentary_movies
FROM filtered_genres AS fg
GROUP BY fg.release_year
ORDER BY fg.release_year DESC;


--SOLUTION USING SUBQUERIES
--ADVANTAGES: By filtering the categories in the innermost query first, the database only joins a tiny fraction of the film_category table to the massive film table saving significant memory and CPU.
--DISADVANTAGES:Poor readability, the deep nesting structure forces you to read the logic inside-out.
SELECT flm.release_year , 
		COALESCE(SUM(CASE WHEN UPPER(fcat_genres.name) = 'DRAMA' 		THEN 1 ELSE 0 END), 0) as number_of_drama_movies, 
		COALESCE(SUM(CASE WHEN UPPER(fcat_genres.name) = 'TRAVEL' 		THEN 1 ELSE 0 END), 0) as number_of_travel_movies, 
		COALESCE(SUM(CASE WHEN UPPER(fcat_genres.name) = 'DOCUMENTARY' THEN 1 ELSE 0 END), 0) as number_of_documentary_movies
FROM public.film flm 
INNER JOIN (
	SELECT fcat.film_id,
			fgenres.name
	FROM public.film_category fcat 
	INNER JOIN (
		SELECT 	cat.category_id,
				cat.name
		FROM public.category cat 
		WHERE UPPER(cat.name) IN ('DRAMA', 'DOCUMENTARY', 'TRAVEL')
	) AS fgenres 	ON fcat.category_id = fgenres.category_id 
)AS fcat_genres 	ON flm.film_id 		= fcat_genres.film_id 
GROUP BY flm.release_year
ORDER BY flm.release_year DESC;





-- --------------------PART 2-------------------------------------------------------------

/*The HR department aims to reward top-performing employees in 2017 
 * with bonuses to recognize their contribution to stores revenue. 
 * Show which three employees generated the most revenue in 2017? */
/*Assumptions: 
 * - staff could work in several stores in a year, please indicate which store the staff worked in (the last one);
 * - if staff processed the payment then he works in the same store; 
 * - take into account only payment_date*/

--SOLUTION USING CTE - The one I would use for a production environment. It would be much asier for a team of engineers to read, debug, and maintain over time. 
--ADVANTAGES: It provides superior top-down readability. By isolating the total revenue calculation and the limit filter into a named block at the top, the main query remains a clean, easy-to-read sequence of joins.
--DISADVANTAGES: It requires slightly more structural syntax (WITH ... AS) compared to a standard join, making the code longer.
WITH top_staff AS(
	SELECT pay.staff_id,
			SUM(pay.amount) AS staff_revenue
	FROM public.payment pay 
	WHERE EXTRACT(YEAR FROM pay.payment_date ) = 2017 
	GROUP BY pay.staff_id
	ORDER BY SUM(pay.amount) DESC
	LIMIT 3
),
last_payment AS (
	SELECT pay.staff_id,
			ts.staff_revenue AS total_revenue, 
			MAX(pay.payment_date) AS last_payment
	FROM public.payment pay 
	INNER JOIN top_staff ts ON pay.staff_id = ts.staff_id
	WHERE EXTRACT(YEAR FROM pay.payment_date ) = 2017 
	GROUP BY pay.staff_id,
			ts.staff_revenue 
)
SELECT (stf.first_name || ' ' || stf.last_name) AS full_name,
		stf.staff_id,
		lpay.total_revenue,
		str.store_id 
FROM staff stf
INNER JOIN last_payment lpay ON stf.staff_id = lpay.staff_id
INNER JOIN store str ON stf.store_id = str.store_id 
GROUP BY stf.first_name ,
			stf.last_name,
			stf.staff_id, 
			lpay.total_revenue,
			str.store_id
ORDER BY lpay.total_revenue DESC,
			str.store_id ASC;

--SOLUTION USING JOIN
-- ADVANTAGES: Extremely easy to read. Because we are linking directly to the staff's currently assigned store, we can do the aggregation, joining, and limiting in a single step. The query optimizer handles this perfectly.
-- DISADVANTAGES: The database must join all 2017 payment rows to the staff and store tables *before* grouping them, which consumes slightly more memory than pre-aggregating.

SELECT (stf.first_name || ' ' || stf.last_name) AS full_name,
       pay.staff_id,
       SUM(pay.amount)                          AS total_revenue,
       str.store_id
FROM public.payment pay
INNER JOIN public.staff stf ON pay.staff_id = stf.staff_id
INNER JOIN public.store str ON stf.store_id = str.store_id
WHERE EXTRACT(YEAR FROM pay.payment_date) = 2017
GROUP BY pay.staff_id,
         stf.first_name,
         stf.last_name,
         str.store_id
ORDER BY total_revenue DESC
LIMIT 3;

--SOLUTION USING SUBQUERIES
-- ADVANTAGES: Highly performant. The subquery aggregates the massive `payment` table down to just the top 3 rows *before* joining to the `staff` and `store` tables. This means the joins are executed on exactly 3 rows instead of thousands.
-- DISADVANTAGES: The nested syntax is slightly harder to read at a glance than a pure JOIN or CTE.
SELECT (stf.first_name || ' ' || stf.last_name) AS full_name,
       stf.staff_id,
       top_staff.total_revenue,
       str.store_id
FROM public.staff stf
INNER JOIN (
    SELECT pay.staff_id,
           SUM(pay.amount) AS total_revenue
    FROM public.payment pay
    WHERE EXTRACT(YEAR FROM pay.payment_date) = 2017
    GROUP BY pay.staff_id
    ORDER BY SUM(pay.amount) DESC
    LIMIT 3
) AS top_staff ON stf.staff_id = top_staff.staff_id
INNER JOIN public.store str ON stf.store_id = str.store_id
ORDER BY top_staff.total_revenue DESC,
         str.store_id ASC;

/*2. The management team wants to identify the most popular movies 
 * and their target audience age groups to optimize marketing efforts. 
 * Show which 5 movies were rented more than others (number of rentals), 
 * and what's the expected age of the audience for these movies? 
 * To determine expected age please use 'Motion Picture Association film rating system'*/

/*SOLUTION USING CTE - I would use this solution, here the early aggregation is critical for performance.
 * The CTE does this flawlessly by identifying the 5 correct film_ids first, 
 * and only decodes the movie titles and ratings at the very end. 
 * It balances elite performance with perfect top-down readability, 
 * avoiding the cluttered GROUP BY clause required by the standard JOIN approach.
*/
--ADVANTAGES: Highly performant and readable. Isolates the aggregation for the 'rental' table. Grabs exactly 5 films and after that combines them to the ratings.
--DISADVANTAGES: Slightly more code.
WITH top_rented_movies AS (
    SELECT inv.film_id,
           COUNT(ren.rental_id) AS number_of_rentals
    FROM public.inventory inv
    INNER JOIN public.rental ren ON inv.inventory_id = ren.inventory_id
    GROUP BY inv.film_id
    ORDER BY COUNT(ren.rental_id) DESC
    LIMIT 5
)
SELECT flm.title,
       trm.number_of_rentals,
       CASE flm.rating
           WHEN 'G'     THEN 'All ages'
           WHEN 'PG'    THEN '7 and older'
           WHEN 'PG-13' THEN '13 and older'
           WHEN 'R'     THEN '17 and older'
           WHEN 'NC-17' THEN '18 and older'
           ELSE 'Unknown'
       END AS expected_age
FROM top_rented_movies trm
INNER JOIN public.film flm ON trm.film_id = flm.film_id
ORDER BY trm.number_of_rentals DESC;

--SOLUTION USING JOIN
-- ADVANTAGES: Uses standard, flat relational mapping with no nested structures.
-- DISADVANTAGES: The database joins the massive 'rental' table before grouping the data. Additionally, we are forced to put `flm.title` and `flm.rating` into the `GROUP BY` clause, which consumes extra memory for sorting string values rather than just integers.
SELECT flm.title,
		COUNT(rent.rental_id) AS rental_count,
		CASE flm.rating
			WHEN 'G' THEN 'All ages'
			WHEN 'PG' THEN 'Parental Guidance Suggested - 7 and older'
			WHEN 'PG-13' THEN 'Parents Strongly Cautioned - 13 and older'
			WHEN 'R' THEN 'Restricted - 17 and older'
			WHEN 'NC-17' THEN 'Adults Only - over 18'
			ELSE 'Unknown'
		END AS audience
FROM film flm 
INNER JOIN inventory inv ON flm.film_id = inv.film_id 
INNER JOIN rental rent ON inv.inventory_id = rent.inventory_id 
GROUP BY flm.film_id,
			flm.title,
			flm.rating 
ORDER BY rental_count DESC
LIMIT 5;

--SOLUTION USING SUBQUERIES
-- ADVANTAGES: Delivers the exact same high performance as the CTE by aggregating the `rental` table down to 5 rows internally before executing the `film` table join.
-- DISADVANTAGES: It disrupts top-down readability and forces the reader to scan the middle of the query to understand how the top 5 filter is being applied.
SELECT flm.title,
       top_rentals.number_of_rentals,
       CASE flm.rating
           WHEN 'G'     THEN 'All ages'
           WHEN 'PG'    THEN '7 and older'
           WHEN 'PG-13' THEN '13 and older'
           WHEN 'R'     THEN '17 and older'
           WHEN 'NC-17' THEN '18 and older'
           ELSE 'Unknown'
       END AS expected_age
FROM public.film flm
INNER JOIN (
    SELECT inv.film_id,
           COUNT(ren.rental_id) AS number_of_rentals
    FROM public.inventory inv
    INNER JOIN public.rental ren ON inv.inventory_id = ren.inventory_id
    GROUP BY inv.film_id
    ORDER BY COUNT(ren.rental_id) DESC
    LIMIT 5
) AS top_rentals ON flm.film_id = top_rentals.film_id
ORDER BY top_rentals.number_of_rentals DESC;



-- --------------------PART 3-------------------------------

/*The stores’ marketing team wants to analyze actors' inactivity periods 
 * to select those with notable career breaks for targeted promotional campaigns, 
 * highlighting their comebacks or consistent appearances to engage customers 
 * with nostalgic or reliable film stars
 * The task can be interpreted in various ways, and here are a few options (provide solutions for each one):
 * V1: gap between the latest release_year and current year per each actor;*/
 


--SOLUTION USING SUBQUERIES (V1)
-- ADVANTAGES: The aggregation is executed inside the subquery first, reducing data volume before joining.
-- DISADVANTAGES: Code readability is reduced 
SELECT 
	ac.first_name,
	ac.last_name,
	MAX(gap_years.release_year),
	EXTRACT(YEAR FROM current_date) - MAX(gap_years.release_year) AS gap
FROM public.actor ac 
INNER JOIN (
			SELECT 
				fa.actor_id,
				flm_gaps.release_year 
			FROM public.film_actor fa 
			INNER JOIN(
						SELECT 
							flm.film_id,
							flm.release_year 
						FROM public.film flm
			)AS flm_gaps ON fa.film_id = flm_gaps.film_id 
)AS gap_years ON ac.actor_id = gap_years.actor_id
GROUP BY ac.actor_id, ac.first_name, ac.last_name 
ORDER BY gap DESC;

--SOLUTION USING JOIN (V1)
-- ADVANTAGES: 
-- DISADVANTAGES:
SELECT 
	ac.first_name,
	ac.last_name,
	MAX(flm.release_year),
	EXTRACT(YEAR FROM current_date) - MAX(flm.release_year) AS gap
FROM public.actor ac 
INNER JOIN film_actor fa ON ac.actor_id = fa.actor_id 
INNER JOIN film flm ON fa.film_id = flm.film_id 
GROUP BY ac.actor_id, ac.first_name, ac.last_name 
ORDER BY gap DESC;

--SOLUTION USING CTE (V1)
--ADVANTAGES: Perfect top-down structure. Isolates the max release year aggregation step cleanly.
--DISADVANTAGES: Slightly overheads the structure for such straightforward aggregate calculation.
WITH actor_latest_year AS(
	SELECT 
		fa.actor_id,
		MAX(flm.release_year) AS last_year
	FROM public.film_actor fa 
	INNER JOIN public.film flm ON fa.film_id = flm.film_id  
	GROUP BY fa.actor_id 
)
SELECT 
	ac.actor_id, 
	ac.first_name,
	ac.last_name,
	EXTRACT(YEAR FROM current_date) - MAX(aly.last_year) AS gap
FROM public.actor ac 
INNER JOIN actor_latest_year aly ON  ac.actor_id = aly.actor_id 
GROUP BY ac.actor_id, ac.first_name, ac.last_name 
ORDER BY gap DESC
;

-- --------------------PART 3-------------------------------

/*The stores’ marketing team wants to analyze actors' inactivity periods 
 * to select those with notable career breaks for targeted promotional campaigns, 
 * highlighting their comebacks or consistent appearances to engage customers 
 * with nostalgic or reliable film stars
 * The task can be interpreted in various ways, and here are a few options (provide solutions for each one):
 * V2: gaps between sequential films per each actor;*/
/*Here is the logic I implemented that another student suggested in the chat:
 * Let's say the actor starred in 2010, 2015, and 2022. 
 * There are two gaps - 5 years (2015-2010) and 7 years (2022-2015). 
 * We should find these gaps and return the greatest, in this case 7 years.
 */

--SOLUTION USING CTE (V2) - The only recommended one that I would actually use in production because it solves a multi-stage aggregation problem cleanly without violating SQL rules or compromising query performance.
-- ADVANTAGES: Highly structured and readable. It isolates the deduplication step into a distinct block before performing the self-join, completely avoiding cartesian products from multiple same-year films.
-- DISADVANTAGES: Requires multiple CTE blocks (`WITH ... AS`), which increases total lines of code.
WITH actor_years AS(
	SELECT DISTINCT	fact.actor_id,
			flm.release_year 
	FROM public.film_actor fact 
	INNER JOIN public.film flm ON fact.film_id  = flm.film_id 
	ORDER BY fact.actor_id, flm.release_year   
), film_gaps AS(
	SELECT ay1.actor_id,
			ay1.release_year AS start_year,
			MIN(ay2.release_year) AS end_year,
			MIN(ay2.release_year) - ay1.release_year AS gap_period 
	FROM actor_years ay1
	INNER JOIN actor_years ay2 ON 	ay1.actor_id = ay2.actor_id AND
									ay2.release_year > ay1.release_year
	GROUP BY 	ay1.actor_id,
				ay1.release_year 
)
SELECT 
	ac.actor_id,
	ac.first_name,
	ac.last_name,
	MAX(fgaps.gap_period) AS max_inactivity_gap
FROM public.actor ac 
INNER JOIN film_gaps fgaps ON ac.actor_id = fgaps.actor_id 
GROUP BY ac.actor_id, ac.first_name, ac.last_name
HAVING MAX(fgaps.gap_period) IS NOT NULL
ORDER BY max_inactivity_gap DESC;

--SOLUTION USING SUBQUERIES (V2)
-- ADVANTAGES: Avoids explicit self-joins in the `FROM` clause by retrieving the immediate next year directly inside a scalar subquery.
-- DISADVANTAGES: Extremely inefficient because the inner subquery runs repeatedly for every film row, causing high database CPU load.
SELECT act.first_name,
       act.last_name,
       MAX(
           (
               SELECT MIN(sub_flm.release_year)
               FROM public.film_actor sub_fact
               INNER JOIN public.film sub_flm ON sub_fact.film_id = sub_flm.film_id
               WHERE sub_fact.actor_id = act.actor_id AND 
                     sub_flm.release_year > flm.release_year
           ) - flm.release_year
       ) AS max_inactivity_gap
FROM public.actor act
INNER JOIN public.film_actor fact ON act.actor_id = fact.actor_id
INNER JOIN public.film       flm  ON fact.film_id  = flm.film_id
GROUP BY act.actor_id,
         act.first_name,
         act.last_name
HAVING MAX(
           (
               SELECT MIN(sub_flm.release_year)
               FROM public.film_actor sub_fact
               INNER JOIN public.film sub_flm ON sub_fact.film_id = sub_flm.film_id
               WHERE sub_fact.actor_id = act.actor_id AND 
                     sub_flm.release_year > flm.release_year
           ) - flm.release_year
       ) IS NOT NULL
ORDER BY max_inactivity_gap DESC,
         act.last_name      ASC;

-- WHY A PURE SINGLE JOIN IS NOT COMPATIBLE:
-- A pure flat JOIN approach without CTEs, subqueries, or window functions is 
-- technically impossible for Part 3 - V2. Finding the greatest consecutive gap 
-- requires two sequential levels of aggregation:
-- 1. Inner Aggregation: Computing MIN(Y2) for each release year Y1 per actor 
--    to calculate individual consecutive gaps (Y2 - Y1).
-- 2. Outer Aggregation: Calculating MAX() across all consecutive gaps for that actor.
-- SQL standard syntax strictly prohibits nesting aggregate functions (e.g., MAX(MIN(Y2) - Y1)) 
-- within a single GROUP BY clause. Therefore, CTEs are mandatory.