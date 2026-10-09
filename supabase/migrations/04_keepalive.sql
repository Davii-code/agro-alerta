-- Keepalive heartbeat
-- Supabase pausa projetos do plano free depois de alguns dias sem atividade.
-- A pipeline diaria (.github/workflows/supabase-keepalive.yml) insere uma linha
-- aqui todos os dias; a escrita conta como atividade e mantem o projeto de pe.
CREATE TABLE IF NOT EXISTS public.keepalive (
    id BIGSERIAL PRIMARY KEY,
    pinged_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    source TEXT NOT NULL DEFAULT 'github-actions',
    note TEXT
);

CREATE INDEX IF NOT EXISTS keepalive_pinged_at_idx ON public.keepalive (pinged_at DESC);

-- A tabela so e escrita pela service role (que ignora RLS). Ninguem mais le
-- nem escreve: RLS ligada e nenhuma policy criada de proposito.
ALTER TABLE public.keepalive ENABLE ROW LEVEL SECURITY;

-- Mantem a tabela pequena: guarda os ultimos 90 dias de batimentos.
CREATE OR REPLACE FUNCTION public.prune_keepalive()
RETURNS void AS $$
BEGIN
    DELETE FROM public.keepalive WHERE pinged_at < NOW() - INTERVAL '90 days';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
