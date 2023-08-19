-- 1 up
CREATE TYPE task_status AS ENUM ('todo', 'in-progress', 'done', 'failed');
CREATE TYPE task_type AS ENUM ('raku-doc-push');

/* task table holds all the tasks. */
CREATE TABLE IF NOT EXISTS task(
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    created TIMESTAMP WITH TIME ZONE DEFAULT now(),
    started TIMESTAMP WITH TIME ZONE,
    completed TIMESTAMP WITH TIME ZONE,

    /* task_type is for the taskrunner to differentiate tasks. */
    status task_status NOT NULL DEFAULT 'todo',
    type task_type NOT NULL DEFAULT 'raku-doc-push',

    detail JSONB NOT NULL,
    pid INTEGER, /* for taskrunner recordkeeping. */

    priority SMALLINT DEFAULT 0,

    /* if job is in progress then started column cannot be null. */
    CONSTRAINT task_status_in_progress_started_not_null_check
        CHECK ( NOT (status = 'in-progress' AND (started IS NULL OR pid IS NULL)) ),

    /* if job has completed then the column cannot be null. */
    CONSTRAINT task_status_done_failed_completed_not_null_check
        CHECK ( NOT (status IN ('done', 'failed') AND completed IS NULL) )
);

/* capture_func executes a NOTIFY. it is used to listen on new row insertions. */
CREATE FUNCTION capture_func()
RETURNS trigger AS
$$
DECLARE
  v_txt TEXT;
BEGIN
  v_txt := format('new %s: %s', TG_OP, NEW.id);
  /* RAISE NOTICE '%', v_txt; */
  EXECUTE FORMAT('NOTIFY task_insert, ''%s''', v_txt);
  RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

CREATE TRIGGER task_new_row_trigger
    BEFORE INSERT ON task
    FOR EACH ROW
    EXECUTE PROCEDURE capture_func();
