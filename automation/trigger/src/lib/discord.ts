type DiscordWebhookMessage = {
  content: string;
};

async function postWebhook(url: string | undefined, message: DiscordWebhookMessage) {
  if (!url) {
    return;
  }

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify(message),
  });

  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`Discord webhook failed: ${response.status} ${detail}`);
  }
}

export async function notifyImportChannel(message: string) {
  await postWebhook(process.env.DISCORD_IMPORT_WEBHOOK_URL, { content: message });
}

export async function notifyFailureChannel(message: string) {
  await postWebhook(process.env.DISCORD_FAILURE_WEBHOOK_URL, { content: message });
}
