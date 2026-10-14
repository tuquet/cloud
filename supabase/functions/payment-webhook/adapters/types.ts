export interface NormalizedWebhookSettlement {
  intentId?: string;
  transferCode?: string;
  providerTxId: string;
  paidAmount: number;
  currency: 'VND' | 'USD' | 'USDT';
  rawPayload: Record<string, unknown>;
}

export interface GatewaySecretConfig {
  webhook_secret?: string;
  api_key?: string;
  [key: string]: string | undefined;
}
