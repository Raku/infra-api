

-- 1 up # Example up migration
create table if not exists public.task_process_log
(
    id      uuid default gen_random_uuid(),
    task_id uuid not null
        constraint task_process_log_task_id_fk
            references public.task
);

comment on table public.task_process_log is 'log output captured from task subprocesses';

comment on constraint task_process_log_task_id_fk on public.task_process_log is 'foreign key to task table';

-- 1 down # Example down migration

drop table if exists task_process_log;
