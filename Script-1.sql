
/*
-- ЧАСТЬ 0. ДИАГНОСТИКА — что в таблице сейчас
-- 0.1. Сколько строк в таблице
SELECT COUNT(*) AS total_rows
FROM obrazzov.obraz_uch;

--0.2. Сколько NULL в ключевых колонках
SELECT
    COUNT(*) FILTER (WHERE "data.general.id" IS NULL)                     AS null_id,
    COUNT(*) FILTER (WHERE "data.general.name" IS NULL)                   AS null_name,
    COUNT(*) FILTER (WHERE "data.general.address.fullAddress" IS NULL)    AS null_addr
FROM obrazzov.obraz_uch;

--ЧАСТЬ 1. ЧИСТКА ДАННЫХ


--1.1. Удаляем строки, где пустой ID 
DELETE FROM obrazzov.obraz_uch
WHERE "data.general.id" IS NULL;

--1.2. Заполняем NULL в названии учреждения заглушкой
UPDATE obrazzov.obraz_uch
SET "data.general.name" = 'Название не указано'
WHERE "data.general.name" IS NULL;

--1.3. Заполняем NULL в полном адресе заглушкой
UPDATE obrazzov.obraz_uch
SET "data.general.address.fullAddress" = 'Адрес не указан'
WHERE "data.general.address.fullAddress" IS NULL;



--ЧАСТЬ 2. РАЗДЕЛ 3.1

--2.1. PRIMARY KEY на "data.general.id"
ALTER TABLE obrazzov.obraz_uch
ADD CONSTRAINT pk_obraz_uch_id
PRIMARY KEY ("data.general.id");

--2.2. SEQUENCE для авто-генерации ID
CREATE SEQUENCE IF NOT EXISTS obrazzov.obraz_uch_id_seq
    START WITH 1000000
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--2.3. DEFAULT
ALTER TABLE obrazzov.obraz_uch
ALTER COLUMN "data.general.id"
SET DEFAULT nextval('obrazzov.obraz_uch_id_seq');

-- 2.4. Привязываем SEQUENCE к колонке 
ALTER SEQUENCE obrazzov.obraz_uch_id_seq
OWNED BY obrazzov.obraz_uch."data.general.id";


-
--ЧАСТЬ 3.
-- 3.1. NOT NULL на название учреждения
ALTER TABLE obrazzov.obraz_uch
ALTER COLUMN "data.general.name" SET NOT NULL;

-- 3.2. NOT NULL на полный адрес
ALTER TABLE obrazzov.obraz_uch
ALTER COLUMN "data.general.address.fullAddress" SET NOT NULL;

-- 3.3. UNIQUE на "data.general.id"
ALTER TABLE obrazzov.obraz_uch
ADD CONSTRAINT uq_obraz_uch_id
UNIQUE ("data.general.id");


--ЧАСТЬ 4. ПРОВЕРКА РЕЗУЛЬТАТА
--4.1. Все ограничения таблицы
SELECT
    conname                   AS constraint_name,
    CASE contype
        WHEN 'p' THEN 'PRIMARY KEY'
        WHEN 'u' THEN 'UNIQUE'
        WHEN 'c' THEN 'CHECK'
        WHEN 'f' THEN 'FOREIGN KEY'
        ELSE contype::text
    END                       AS constraint_type,
    pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'obrazzov.obraz_uch'::regclass
ORDER BY contype, conname;

--4.2. NOT NULL колонки таблицы
SELECT
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'obrazzov'
  AND table_name = 'obraz_uch'
  AND is_nullable = 'NO'
ORDER BY column_name;

--4.3. Связь SEQUENCE ↔ колонка
SELECT
    seq.relname AS sequence_name,
    tbl.relname AS table_name,
    col.attname AS column_name
FROM pg_class seq
JOIN pg_depend d
    ON d.objid = seq.oid
   AND d.deptype = 'a'
JOIN pg_class tbl
    ON tbl.oid = d.refobjid
JOIN pg_attribute col
    ON col.attrelid = tbl.oid
   AND col.attnum = d.refobjsubid
WHERE seq.relkind = 'S'
  AND tbl.relname = 'obraz_uch';

--4.4. DEFAULT на колонке ID
SELECT
    column_name,
    column_default
FROM information_schema.columns
WHERE table_schema = 'obrazzov'
  AND table_name = 'obraz_uch'
  AND column_name = 'data.general.id';

--3.3.1. Оставляем только учреждения Вологодской области
DELETE FROM obrazzov.obraz_uch
WHERE "data.general.address.fullAddress" NOT LIKE '%Вологодская%'
   OR "data.general.address.fullAddress" IS NULL;
   -- Полный список оставшихся учреждений
SELECT 
    "data.general.id"                     AS id,
    "data.general.name"                   AS name,
    "data.general.locale.name"            AS city,
    "data.general.address.fullAddress"    AS full_address
FROM obrazzov.obraz_uch
ORDER BY "data.general.locale.name", "data.general.name";

--3.3.2
ALTER TABLE obrazzov.obraz_uch
    ADD COLUMN geom geometry(Point, 4326);

SELECT column_name, data_type, udt_name
FROM information_schema.columns
WHERE table_schema = 'obrazzov'
  AND table_name = 'obraz_uch'
  AND column_name = 'geom';

--3.3.3–3.3.4
UPDATE obrazzov.obraz_uch
SET geom = ST_SetSRID(
        ST_GeomFromGeoJSON("data.general.address.mapPosition"::text),
        4326
    )
WHERE "data.general.address.mapPosition" IS NOT NULL
  AND "data.general.address.mapPosition"::text <> 'null'
  AND "data.general.address.mapPosition"::text <> ''
  AND "data.general.address.mapPosition"::text LIKE '%coordinates%';

SELECT COUNT(*) FILTER (WHERE geom IS NOT NULL) AS with_geom,
       COUNT(*) FILTER (WHERE geom IS NULL)     AS without_geom
FROM obrazzov.obraz_uch;

SELECT 
    "data.general.name" AS name,
    ST_AsText(geom)     AS wkt,
    ST_SRID(geom)       AS srid
FROM obrazzov.obraz_uch
WHERE geom IS NOT NULL
LIMIT 5;

-- 3.3.5. Создаём таблицу тегов
CREATE SEQUENCE obrazzov.tags_id_seq START WITH 1 INCREMENT BY 1;

CREATE TABLE obrazzov.tags (
    id          BIGINT       NOT NULL DEFAULT nextval('obrazzov.tags_id_seq'),
    name        VARCHAR(255) NOT NULL,
    slug        VARCHAR(255),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT tags_pkey PRIMARY KEY (id),
    CONSTRAINT tags_name_unique UNIQUE (name)
);

SELECT * FROM obrazzov.tags;
-- таблица создана, но пока пустая

--3.3.6 заполнение таблицы tags
INSERT INTO obrazzov.tags (name, slug)
SELECT DISTINCT
       (elem->>'name')    AS name,
       (elem->>'sysName') AS slug
FROM obrazzov.obraz_uch,
     LATERAL jsonb_array_elements("data.general.tags") AS elem
WHERE "data.general.tags" IS NOT NULL
  AND jsonb_typeof("data.general.tags") = 'array'
ON CONFLICT (name) DO NOTHING;

SELECT * FROM obrazzov.tags ORDER BY id;
--3.3.7 Промежуточная таблица «многие ко многим»
CREATE TABLE obrazzov.m2m_obraz_uch_tags (
    obraz_uch_id BIGINT NOT NULL,
    tag_id       BIGINT NOT NULL,
    CONSTRAINT m2m_pkey PRIMARY KEY (obraz_uch_id, tag_id),
    CONSTRAINT m2m_obraz_uch_fk FOREIGN KEY (obraz_uch_id)
        REFERENCES obrazzov.obraz_uch ("data.general.id")
        ON DELETE CASCADE,
    CONSTRAINT m2m_tag_fk FOREIGN KEY (tag_id)
        REFERENCES obrazzov.tags (id)
        ON DELETE CASCADE
);

--Заполнение таблицы "многие ко многим"
INSERT INTO obrazzov.m2m_obraz_uch_tags (obraz_uch_id, tag_id)
SELECT DISTINCT
       c."data.general.id" AS obraz_uch_id,
       t.id                AS tag_id
FROM obrazzov.obraz_uch c,
     LATERAL jsonb_array_elements(c."data.general.tags") AS elem
JOIN obrazzov.tags t
     ON t.name = (elem->>'name')
WHERE c."data.general.tags" IS NOT NULL
  AND jsonb_typeof(c."data.general.tags") = 'array'
ON CONFLICT DO NOTHING;

--Проверка
SELECT COUNT(*) FROM obrazzov.m2m_obraz_uch_tags;

--3.3.8. Индексы
CREATE INDEX idx_m2m_obraz_uch_id
    ON obrazzov.m2m_obraz_uch_tags (obraz_uch_id);

CREATE INDEX idx_m2m_tag_id
    ON obrazzov.m2m_obraz_uch_tags (tag_id);

CREATE INDEX idx_obraz_uch_geom
    ON obrazzov.obraz_uch
    USING GIST (geom);

--Проверка
SELECT indexname
FROM pg_indexes
WHERE schemaname = 'obrazzov'
  AND tablename IN ('obraz_uch', 'm2m_obraz_uch_tags')
ORDER BY indexname;
*/
