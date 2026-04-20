import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { getSupabaseAdmin } from "../_shared/supabase.ts";
import { downloadImportJson } from "../_shared/storage.ts";
import { recordArtifact, updateJobStatus } from "../_shared/job-status.ts";

interface PromotePayload {
  jobId: string;
  seedSqlPath: string;
  environment: string;
  approvedBy?: string;
}

async function executeSeedSql(sqlContent: string): Promise<{
  ok: boolean;
  rowsAffected?: number;
  error?: string;
}> {
  const admin = getSupabaseAdmin();

  try {
    // Execute SQL directly
    // Note: This will run the entire SQL as a single statement
    // The SQL should include BEGIN/COMMIT for transaction safety
    const { error, count } = await admin.rpc("exec_sql", {
      sql_text: sqlContent,
    });

    if (error) {
      return { ok: false, error: error.message };
    }

    return { ok: true, rowsAffected: count ?? 0 };
  } catch (error) {
    return {
      ok: false,
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  try {
    const payload: PromotePayload = await req.json();

    // Check if promotion is enabled
    const enablePromotion = Deno.env.get("ENABLE_STORY_IMPORT_PROMOTE");
    if (enablePromotion !== "true") {
      await recordArtifact(payload.jobId, "promote_request", null, {
        environment: payload.environment,
        approvedBy: payload.approvedBy ?? null,
        skipped: true,
        reason: "ENABLE_STORY_IMPORT_PROMOTE is not enabled",
      });

      return new Response(
        JSON.stringify({
          ok: true,
          skipped: true,
          environment: payload.environment,
        }),
        {
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Download seed SQL
    const seedSql = await downloadImportJson(payload.seedSqlPath);

    // Execute SQL
    const executionResult = await executeSeedSql(seedSql);

    if (!executionResult.ok) {
      await updateJobStatus(payload.jobId, "failed", {
        promotionError: executionResult.error,
      });

      return new Response(
        JSON.stringify({
          ok: false,
          error: executionResult.error,
        }),
        {
          status: 500,
          headers: { "Content-Type": "application/json" },
        },
      );
    }

    // Record success
    await recordArtifact(payload.jobId, "promote_request", null, {
      environment: payload.environment,
      approvedBy: payload.approvedBy ?? null,
      rowsAffected: executionResult.rowsAffected,
    });

    await updateJobStatus(payload.jobId, "promoted", {
      promotedEnvironment: payload.environment,
      rowsAffected: executionResult.rowsAffected,
      approvedBy: payload.approvedBy ?? null,
    });

    return new Response(
      JSON.stringify({
        ok: true,
        skipped: false,
        environment: payload.environment,
        rowsAffected: executionResult.rowsAffected,
      }),
      {
        headers: { "Content-Type": "application/json" },
      },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);

    return new Response(
      JSON.stringify({
        ok: false,
        error: message,
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
});
