-- ---------Task 1---------------

/*
Choose your real top-3 favorite movies
(released in different years, belong to different genres)
and add them to the 'film' table
(films with the title Film1, Film2, etc - will not be taken into account and grade will be reduced by 20%)
Fill in rental rates with 4.99, 9.99 and 19.99
and rental durations with 1, 2 and 3 weeks respectively.

Add the real actors who play leading roles in your favorite movies
to the 'actor' and 'film_actor' tables (6 or more actors in total).
Actors with the name Actor1, Actor2, etc - will not be taken into account and grade will be reduced by 20%.
You must decide how to identify actors that already exist in the system and how to avoid duplicates

Add your favorite movies to any store's inventory.

Alter any existing customer in the database with at least 43 rental and 43 payment records.
Change their personal data to yours (first name, last name, address, etc.).
You can use any existing address from the "address" table.
Please do not perform any updates on the "address" table, as this can impact multiple records with the same address.

Remove any records related to you (as a customer) from all tables except 'Customer' and 'Inventory'

Rent your favorite movies from the store they are in and pay for them
(add corresponding records to the database to represent this activity)
(Note: to insert the payment_date into the table payment, you can create a new partition
(see the scripts to install the training database ) or add records for the
first half of 2017)

Note:
-Don't forget to insert the schema name before table names
-All new & updated records must have 'last_update' field set to 'current_date'
-Don't forget to add COMMIT after each subtask.
-INSERT sub-tasks - provide justification:
	-how you ensured data uniqueness
	-how relationships between tables are established


DELETE sub-tasks - provide justification:
	-why deleting from tables is safe
	-how you ensured no unintended data loss occurs

-Your scripts must be rerunnable/reusable and don't produces duplicates.
-You can use WHERE NOT EXISTS, IF NOT EXISTS, ON CONFLICT DO NOTHING, etc.
-Double-check your DELETEs and UPDATEs with SELECT query before committing the transaction!!!
-Don't hardcode IDs. Instead of construction INSERT INTO … VALUES use INSERT INTO … SELECT … and explain what the advantage is
-Don't forget to add RETURNING
-In the comments explain:
	-why a separate transaction is used
	-what would happen if the transaction fails
	-whether rollback is possible and what data would be affected
	-how referential integrity is preserved
	-how your script avoids duplicates

*/



-- ------------SOLUTION-----------------------------------

/*Choose your real top-3 favorite movies
(released in different years, belong to different genres)
and add them to the 'film' table
(films with the title Film1, Film2, etc - will not be taken into account and grade will be reduced by 20%)
Fill in rental rates with 4.99, 9.99 and 19.99
and rental durations with 1, 2 and 3 weeks respectively.*/

/* We use a separate transaction for each film so if a films insert is unsuccessful the other ones are committed independently(isolation between transactions)
 * If the transaction fails the film is not inserted into the table and it is not being connected to the category table.
 * A rollback is possible and it affects the current transaction without interrupting the other running ones.
 * Referential integrity is preserved by filtering by the language and category name, not hardcoding it by the ID
 * My script avoids duplicates by using AND NOT EXISTS for each insert that is being executed.
 */

--1.Adding the first film 'Pirates of the Caribbean'
BEGIN;

INSERT INTO public.film (
	title, 
    description, 
    release_year, 
    language_id, 
    rental_duration, 
    rental_rate, 
    length, 
    replacement_cost, 
    rating, 
    last_update
)
SELECT 
	'Pirates of the Caribbean: The Curse of the Black Pearl',
    'Blacksmith Will Turner teams up with eccentric pirate Captain Jack Sparrow to save his love.',
    2003,
    lan.language_id,
    7,
    4.99,
    143,
    19.99,
    'PG-13'::public.mpaa_rating,
    CURRENT_DATE
FROM public."language" lan 
WHERE lan.name = 'English'
AND NOT EXISTS(
	SELECT 1
	FROM public.film flm
	WHERE flm.title = 'Pirates of the Caribbean: The Curse of the Black Pearl'
		AND flm.release_year = 2003
)
RETURNING film_id;

--Establish the relationship between the film('Pirates of the Caribbean: The Curse of the Black Pearl') and it's category('Action')
INSERT INTO public.film_category(film_id, category_id, last_update)
SELECT flm.film_id, cat.category_id, CURRENT_DATE
FROM public.film flm
INNER JOIN public.category cat ON cat."name" = 'Action'
WHERE flm.title = 'Pirates of the Caribbean: The Curse of the Black Pearl'
AND NOT EXISTS (
	SELECT 1
	FROM public.film_category fc 
	WHERE fc.film_id = flm.film_id AND fc.category_id = cat.category_id 
);
COMMIT;



--2.Adding the second film 'The Lord of the Rings: The Fellowship of the Ring'
BEGIN;
INSERT INTO public.film (
	title, 
    description, 
    release_year, 
    language_id, 
    rental_duration, 
    rental_rate, 
    length, 
    replacement_cost, 
    rating, 
    last_update
)
SELECT
	'The Lord of the Rings: The Fellowship of the Ring',
    'A meek Hobbit from the Shire and eight companions set out on a journey to destroy the One Ring.',
    2001,
    l.language_id ,
    14,
    9.99,
    178,
    24.99,
    'PG-13',
    CURRENT_DATE
FROM public."language" l 
WHERE l."name" = 'English'
AND NOT EXISTS(
	SELECT 1
	FROM public.film f 
	WHERE f.title = 'The Lord of the Rings: The Fellowship of the Ring'
		AND f.release_year = 2001)
RETURNING film_id;

--Establish the relationship between the film('The Lord of the Rings: The Fellowship of the Ring') and it's category('Fantasy')
INSERT INTO film_category (film_id, category_id, last_update)
SELECT 
	f.film_id,
	c.category_id,
	now()
FROM film f 
INNER JOIN category c ON c."name" = 'Fantasy'
WHERE f.title = 'The Lord of the Rings: The Fellowship of the Ring'
AND NOT EXISTS(
	SELECT 1 
	FROM public.film_category fc 
	WHERE fc.film_id = f.film_id AND fc.category_id = c.category_id );

COMMIT;



--3.Adding the third film 'Harry Potter and the Chamber of Secrets'
BEGIN;
INSERT INTO public.film (
	title, 
    description, 
    release_year, 
    language_id, 
    rental_duration, 
    rental_rate, 
    length, 
    replacement_cost, 
    rating, 
    last_update
)
SELECT 
	'Harry Potter and the Chamber of Secrets',
    'An ancient prophecy seems to be coming true when a mysterious presence begins stalking the corridors of a school of magic.',
    2002,
    l.language_id,
    21,
    19.99,
    161,
    29.99,
    'PG',
    CURRENT_DATE
FROM public."language" l 
WHERE l."name" = 'English'
AND NOT EXISTS(
SELECT 1
FROM public.film f 
WHERE f.title = 'Harry Potter and the Chamber of Secrets'
	AND f.release_year = 2002)
RETURNING film_id;

--Establish the relationship between the film('Harry Potter and the Chamber of Secrets') and it's category('Family')
INSERT INTO public.film_category (film_id, category_id, last_update )
SELECT
	f.film_id,
	c.category_id,
	now()
FROM film f 
INNER JOIN category c ON c."name" = 'Family'
WHERE f.title = 'Harry Potter and the Chamber of Secrets'
AND NOT EXISTS (
SELECT 1 
FROM film_category fc 
WHERE fc.film_id = f.film_id AND fc.category_id = c.category_id );

COMMIT;

/*Add the real actors who play leading roles in your favorite movies
to the 'actor' and 'film_actor' tables (6 or more actors in total).
Actors with the name Actor1, Actor2, etc - will not be taken into account and grade will be reduced by 20%.
You must decide how to identify actors that already exist in the system and how to avoid duplicates*/

BEGIN;
INSERT INTO public.actor (
	first_name,
	last_name,
	last_update 
)
SELECT
	new_actors.f_name,
	new_actors.l_name,
	now()
FROM (
	VALUES
		('JOHNNY', 'DEPP'),
	    ('ORLANDO', 'BLOOM'),
	    ('ELIJAH', 'WOOD'),
	    ('IAN', 'MCKELLEN'),
	    ('DANIEL', 'RADCLIFFE'),
	    ('EMMA', 'WATSON')
) AS new_actors(f_name, l_name)
WHERE NOT EXISTS (
	SELECT 1
	FROM public.actor a 
	WHERE a.first_name = new_actors.f_name 
		AND a.last_name = new_actors.l_name )
RETURNING actor_id, first_name, last_name;

INSERT INTO public.film_actor (actor_id, film_id, last_update )
SELECT a.actor_id, f.film_id, CURRENT_DATE
FROM (
    VALUES 
        ('JOHNNY', 'DEPP', 'Pirates of the Caribbean: The Curse of the Black Pearl', 2003),
        ('ORLANDO', 'BLOOM', 'Pirates of the Caribbean: The Curse of the Black Pearl', 2003),
        ('ELIJAH', 'WOOD', 'The Lord of the Rings: The Fellowship of the Ring', 2001),
        ('IAN', 'MCKELLEN', 'The Lord of the Rings: The Fellowship of the Ring', 2001),
        ('DANIEL', 'RADCLIFFE', 'Harry Potter and the Chamber of Secrets', 2002),
        ('EMMA', 'WATSON', 'Harry Potter and the Chamber of Secrets', 2002)
) AS map(first_name, last_name, film_title, release_year)
JOIN public.actor a ON a.first_name = map.first_name AND a.last_name = map.last_name 
JOIN public.film f ON f.title = map.film_title AND f.release_year = map.release_year 
WHERE NOT EXISTS(
	SELECT 1
	FROM public.film_actor fa 
	WHERE fa.actor_id = a.actor_id AND fa.film_id = f.film_id )
RETURNING actor_id, film_id;

COMMIT;

ROLLBACK;
/*Add your favorite movies to any store's inventory.*/
BEGIN;
INSERT INTO public.inventory (film_id, store_id, last_update )
SELECT 
	f.film_id,
	s.store_id,
	CURRENT_DATE
FROM (
	VALUES
		('Pirates of the Caribbean: The Curse of the Black Pearl', 2003),
        ('The Lord of the Rings: The Fellowship of the Ring', 2001),
        ('Harry Potter and the Chamber of Secrets', 2002)
) AS new_films(title, release_year)
JOIN public.film f ON f.title = new_films.title AND f.release_year = new_films.release_year 
CROSS JOIN (
	SELECT MIN(s.store_id) AS store_id
	FROM public.store s 
)AS s
WHERE NOT EXISTS(
	SELECT 1 
	FROM public.inventory i 
	WHERE f.film_id = i.film_id
		AND s.store_id = i.store_id )
RETURNING film_id, store_id;
COMMIT;

/*Alter any existing customer in the database with at least 43 rental and 43 payment records.
Change their personal data to yours (first name, last name, address, etc.).
You can use any existing address from the "address" table.
Please do not perform any updates on the "address" table, as this can impact multiple records with the same address.*/


BEGIN;
UPDATE public.customer
SET
	first_name = 'Yuliyana',
	last_name = 'Mravova',
	email = 'yuliyanamravova@gmail.com',
	address_id = (
		SELECT MIN(address_id)
		FROM public.address
	),
	last_update = CURRENT_DATE
WHERE customer_id  = (
	SELECT c.customer_id 
	FROM public.customer c 
	INNER JOIN public.rental r ON r.customer_id = c.customer_id 
	INNER JOIN public.payment p ON p.customer_id = c.customer_id 
	GROUP BY (c.customer_id)
	HAVING COUNT(DISTINCT p.payment_id  ) >= 43 AND COUNT(DISTINCT r.rental_id ) >= 43
	LIMIT 1
	)
RETURNING customer_id, first_name, last_name, email, address_id;

COMMIT;


/*Remove any records related to you (as a customer) from all tables except 'Customer' and 'Inventory'*/
BEGIN;
DELETE FROM public.payment 
WHERE customer_id = (
	SELECT c.customer_id 
	FROM public.customer c 
	WHERE c.first_name = 'Yuliyana' AND c.last_name = 'Mravova')
RETURNING payment_id, customer_id;

DELETE FROM public.rental 
WHERE customer_id = (
	SELECT c.customer_id 
	FROM public.customer c 
	WHERE c.first_name = 'Yuliyana' AND c.last_name = 'Mravova')
RETURNING rental_id, customer_id;

COMMIT;

/*Rent your favorite movies from the store they are in and pay for them
(add corresponding records to the database to represent this activity)
(Note: to insert the payment_date into the table payment, you can create a new partition
(see the scripts to install the training database ) or add records for the
first half of 2017)*/

BEGIN;

WITH targeted_customer AS(
	SELECT c.customer_id 
	FROM public.customer c 
	WHERE c.first_name = 'Yuliyana'
		AND c.last_name = 'Mravova'
),
new_rentals AS(
	INSERT INTO public.rental (
		rental_date, 
		inventory_id, 
		customer_id, 
		return_date, 
		staff_id, 
		last_update
	)
	SELECT 
		'2017-05-15 10:00:00',
        i.inventory_id,
        tc.customer_id,
        '2017-05-22 10:00:00',
        s.staff_id,
        CURRENT_DATE
	FROM targeted_customer tc
	CROSS JOIN (
		VALUES 
			('Pirates of the Caribbean: The Curse of the Black Pearl', 2003),
            ('The Lord of the Rings: The Fellowship of the Ring', 2001),
            ('Harry Potter and the Chamber of Secrets', 2002)
	) AS target_films(title, release_year)
	INNER JOIN public.film f ON f.title = target_films.title AND f.release_year = target_films.release_year 
	INNER JOIN public.inventory i ON i.film_id = f.film_id 
	INNER JOIN public.staff s ON s.store_id = i.store_id 
	ON CONFLICT (rental_date, inventory_id, customer_id) DO NOTHING
	RETURNING rental_id, customer_id, staff_id, inventory_id
)

INSERT INTO public.payment (
	customer_id,
	staff_id,
	rental_id,
	amount,
	payment_date
)
SELECT 
	nr.customer_id,
    nr.staff_id,
    nr.rental_id,
    f.rental_rate,
    '2017-05-15 10:05:00'
FROM new_rentals nr
JOIN public.inventory i ON i.inventory_id = nr.inventory_id
JOIN public.film f ON f.film_id = i.film_id
ON CONFLICT DO NOTHING
RETURNING payment_id, customer_id, rental_id, amount, payment_date;

COMMIT;

SELECT 
    r.rental_id, 
    f.title, 
    r.rental_date, 
    r.return_date
FROM public.rental r
JOIN public.customer c ON c.customer_id = r.customer_id
JOIN public.inventory i ON i.inventory_id = r.inventory_id
JOIN public.film f ON f.film_id = i.film_id
WHERE c.first_name = 'Yuliyana' 
  AND c.last_name = 'Mravova';

SELECT f.title, i.inventory_id, i.store_id
FROM public.film f
LEFT JOIN public.inventory i ON i.film_id = f.film_id
WHERE f.title IN (
    'Pirates of the Caribbean: The Curse of the Black Pearl',
    'The Lord of the Rings: The Fellowship of the Ring',
    'Harry Potter and the Chamber of Secrets'
);


	
	
	
	