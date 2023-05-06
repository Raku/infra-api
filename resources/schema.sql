CREATE TYPE task_status AS ENUM ('todo', 'in-progress', 'done', 'failed');

CREATE TABLE IF NOT EXISTS task(
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created TIMESTAMP WITH TIME ZONE DEFAULT now()
    status task_status NOT NULL DEFAULT 'todo',
    completed TIMESTAMP WITH TIME ZONE,
    detail JSONB NOT NULL
);

-- capture_func executes a NOTIFY. it is used to listen on new row insertions.
CREATE FUNCTION capture_func()
RETURNS trigger AS
$$
DECLARE
  v_txt text;
BEGIN
  v_txt := format('new insert on %s, %s', TG_OP, NEW);
  RAISE NOTICE '%', v_txt;
    EXECUTE FORMAT('NOTIFY task_insert, ''%s''', v_txt);
  RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER task_new_row_trigger BEFORE INSERT
       ON t_message
       FOR EACH ROW EXECUTE PROCEDURE capture_func();
