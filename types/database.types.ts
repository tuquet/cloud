export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.17"
  }
  automation: {
    Tables: {
      execution_logs: {
        Row: {
          id: number
          job_id: string
          level: Database["automation"]["Enums"]["log_level"]
          logged_at: string
          message: string
          node_id: string | null
          payload: Json
          step_name: string | null
          tenant_id: string
        }
        Insert: {
          id?: never
          job_id: string
          level?: Database["automation"]["Enums"]["log_level"]
          logged_at?: string
          message: string
          node_id?: string | null
          payload?: Json
          step_name?: string | null
          tenant_id: string
        }
        Update: {
          id?: never
          job_id?: string
          level?: Database["automation"]["Enums"]["log_level"]
          logged_at?: string
          message?: string
          node_id?: string | null
          payload?: Json
          step_name?: string | null
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "execution_logs_job_id_fkey"
            columns: ["job_id"]
            isOneToOne: false
            referencedRelation: "jobs"
            referencedColumns: ["id"]
          },
        ]
      }
      jobs: {
        Row: {
          completed_tasks: number
          created_at: string
          ended_at: string | null
          error_message: string | null
          failed_tasks: number
          id: string
          name: string
          parameters: Json
          result_summary: Json
          started_at: string | null
          status: Database["automation"]["Enums"]["job_status"]
          tenant_id: string
          total_tasks: number
          triggered_by: string | null
          updated_at: string
          worker_id: string | null
          workflow_id: string | null
        }
        Insert: {
          completed_tasks?: number
          created_at?: string
          ended_at?: string | null
          error_message?: string | null
          failed_tasks?: number
          id?: string
          name: string
          parameters?: Json
          result_summary?: Json
          started_at?: string | null
          status?: Database["automation"]["Enums"]["job_status"]
          tenant_id: string
          total_tasks?: number
          triggered_by?: string | null
          updated_at?: string
          worker_id?: string | null
          workflow_id?: string | null
        }
        Update: {
          completed_tasks?: number
          created_at?: string
          ended_at?: string | null
          error_message?: string | null
          failed_tasks?: number
          id?: string
          name?: string
          parameters?: Json
          result_summary?: Json
          started_at?: string | null
          status?: Database["automation"]["Enums"]["job_status"]
          tenant_id?: string
          total_tasks?: number
          triggered_by?: string | null
          updated_at?: string
          worker_id?: string | null
          workflow_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fk_automation_job_workflow"
            columns: ["tenant_id", "workflow_id"]
            isOneToOne: false
            referencedRelation: "workflows"
            referencedColumns: ["tenant_id", "id"]
          },
        ]
      }
      packages: {
        Row: {
          created_at: string
          created_by: string | null
          data: Json
          deleted_at: string | null
          description: string | null
          icon: string
          id: string
          inputs: Json
          is_external: boolean
          name: string
          outputs: Json
          settings: Json
          status: Database["automation"]["Enums"]["workflow_status"]
          tenant_id: string
          updated_at: string
          variables: Json
          version: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          data?: Json
          deleted_at?: string | null
          description?: string | null
          icon?: string
          id?: string
          inputs?: Json
          is_external?: boolean
          name: string
          outputs?: Json
          settings?: Json
          status?: Database["automation"]["Enums"]["workflow_status"]
          tenant_id: string
          updated_at?: string
          variables?: Json
          version?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          data?: Json
          deleted_at?: string | null
          description?: string | null
          icon?: string
          id?: string
          inputs?: Json
          is_external?: boolean
          name?: string
          outputs?: Json
          settings?: Json
          status?: Database["automation"]["Enums"]["workflow_status"]
          tenant_id?: string
          updated_at?: string
          variables?: Json
          version?: string
        }
        Relationships: []
      }
      schedules: {
        Row: {
          created_at: string
          created_by: string | null
          cron_expression: string
          id: string
          is_active: boolean
          last_run_at: string | null
          name: string
          next_run_at: string | null
          tenant_id: string
          timezone: string
          updated_at: string
          workflow_id: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          cron_expression: string
          id?: string
          is_active?: boolean
          last_run_at?: string | null
          name: string
          next_run_at?: string | null
          tenant_id: string
          timezone?: string
          updated_at?: string
          workflow_id: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          cron_expression?: string
          id?: string
          is_active?: boolean
          last_run_at?: string | null
          name?: string
          next_run_at?: string | null
          tenant_id?: string
          timezone?: string
          updated_at?: string
          workflow_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "fk_automation_schedules_workflow"
            columns: ["tenant_id", "workflow_id"]
            isOneToOne: false
            referencedRelation: "workflows"
            referencedColumns: ["tenant_id", "id"]
          },
        ]
      }
      workflows: {
        Row: {
          created_at: string
          created_by: string | null
          deleted_at: string | null
          description: string | null
          graph_data: Json
          id: string
          name: string
          settings: Json
          status: Database["automation"]["Enums"]["workflow_status"]
          tenant_id: string
          updated_at: string
          variables: Json
          version: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          description?: string | null
          graph_data?: Json
          id?: string
          name: string
          settings?: Json
          status?: Database["automation"]["Enums"]["workflow_status"]
          tenant_id: string
          updated_at?: string
          variables?: Json
          version?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          description?: string | null
          graph_data?: Json
          id?: string
          name?: string
          settings?: Json
          status?: Database["automation"]["Enums"]["workflow_status"]
          tenant_id?: string
          updated_at?: string
          variables?: Json
          version?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      claim_next_job: {
        Args: { p_batch_size?: number; p_worker_id: string }
        Returns: {
          completed_tasks: number
          created_at: string
          ended_at: string | null
          error_message: string | null
          failed_tasks: number
          id: string
          name: string
          parameters: Json
          result_summary: Json
          started_at: string | null
          status: Database["automation"]["Enums"]["job_status"]
          tenant_id: string
          total_tasks: number
          triggered_by: string | null
          updated_at: string
          worker_id: string | null
          workflow_id: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "jobs"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      reap_stale_jobs: { Args: { p_stale_interval?: string }; Returns: number }
    }
    Enums: {
      job_status:
        | "pending"
        | "queued"
        | "running"
        | "paused"
        | "completed"
        | "failed"
        | "cancelled"
      log_level: "trace" | "debug" | "info" | "warn" | "error" | "fatal"
      workflow_status: "draft" | "published" | "archived"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  billing: {
    Tables: {
      bank_receiving_accounts: {
        Row: {
          account_name: string
          account_no: string
          bank_bin: string
          bank_name: string
          created_at: string
          current_daily_total: number
          daily_limit_vnd: number
          daily_reset_at: string
          id: string
          is_active: boolean
          metadata: Json
          priority: number
          qr_template: string
          status: string
          updated_at: string
        }
        Insert: {
          account_name: string
          account_no: string
          bank_bin: string
          bank_name: string
          created_at?: string
          current_daily_total?: number
          daily_limit_vnd?: number
          daily_reset_at?: string
          id: string
          is_active?: boolean
          metadata?: Json
          priority?: number
          qr_template?: string
          status?: string
          updated_at?: string
        }
        Update: {
          account_name?: string
          account_no?: string
          bank_bin?: string
          bank_name?: string
          created_at?: string
          current_daily_total?: number
          daily_limit_vnd?: number
          daily_reset_at?: string
          id?: string
          is_active?: boolean
          metadata?: Json
          priority?: number
          qr_template?: string
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      payment_gateway_secrets: {
        Row: {
          gateway_id: string
          secret_config: Json
          updated_at: string
        }
        Insert: {
          gateway_id: string
          secret_config?: Json
          updated_at?: string
        }
        Update: {
          gateway_id?: string
          secret_config?: Json
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payment_gateway_secrets_gateway_id_fkey"
            columns: ["gateway_id"]
            isOneToOne: true
            referencedRelation: "payment_gateways"
            referencedColumns: ["id"]
          },
        ]
      }
      payment_gateways: {
        Row: {
          channel: Database["billing"]["Enums"]["payment_channel"]
          created_at: string
          currency: string
          driver: string
          id: string
          is_active: boolean
          name: string
          public_config: Json
          rate_per_credit: number
          sort_order: number
          updated_at: string
        }
        Insert: {
          channel: Database["billing"]["Enums"]["payment_channel"]
          created_at?: string
          currency?: string
          driver: string
          id: string
          is_active?: boolean
          name: string
          public_config?: Json
          rate_per_credit?: number
          sort_order?: number
          updated_at?: string
        }
        Update: {
          channel?: Database["billing"]["Enums"]["payment_channel"]
          created_at?: string
          currency?: string
          driver?: string
          id?: string
          is_active?: boolean
          name?: string
          public_config?: Json
          rate_per_credit?: number
          sort_order?: number
          updated_at?: string
        }
        Relationships: []
      }
      payment_intents: {
        Row: {
          amount_credits: number
          buyer_email: string | null
          checkout_payload: Json
          created_at: string
          created_by: string | null
          expires_at: string
          gateway_id: string
          id: string
          paid_at: string | null
          pay_amount: number
          pay_currency: string
          provider_tx_id: string | null
          status: Database["billing"]["Enums"]["payment_intent_status"]
          target_id: string
          target_type: Database["billing"]["Enums"]["payment_target_type"]
          tenant_id: string | null
          transfer_code: string
          updated_at: string
        }
        Insert: {
          amount_credits: number
          buyer_email?: string | null
          checkout_payload?: Json
          created_at?: string
          created_by?: string | null
          expires_at?: string
          gateway_id: string
          id?: string
          paid_at?: string | null
          pay_amount: number
          pay_currency: string
          provider_tx_id?: string | null
          status?: Database["billing"]["Enums"]["payment_intent_status"]
          target_id: string
          target_type: Database["billing"]["Enums"]["payment_target_type"]
          tenant_id?: string | null
          transfer_code: string
          updated_at?: string
        }
        Update: {
          amount_credits?: number
          buyer_email?: string | null
          checkout_payload?: Json
          created_at?: string
          created_by?: string | null
          expires_at?: string
          gateway_id?: string
          id?: string
          paid_at?: string | null
          pay_amount?: number
          pay_currency?: string
          provider_tx_id?: string | null
          status?: Database["billing"]["Enums"]["payment_intent_status"]
          target_id?: string
          target_type?: Database["billing"]["Enums"]["payment_target_type"]
          tenant_id?: string | null
          transfer_code?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payment_intents_gateway_id_fkey"
            columns: ["gateway_id"]
            isOneToOne: false
            referencedRelation: "payment_gateways"
            referencedColumns: ["id"]
          },
        ]
      }
      plans: {
        Row: {
          created_at: string
          description: string | null
          id: string
          is_active: boolean
          max_members: number
          max_monthly_runs: number
          max_storage_mb: number
          metadata: Json
          name: string
          price_monthly_usd: number
        }
        Insert: {
          created_at?: string
          description?: string | null
          id: string
          is_active?: boolean
          max_members?: number
          max_monthly_runs?: number
          max_storage_mb?: number
          metadata?: Json
          name: string
          price_monthly_usd?: number
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          max_members?: number
          max_monthly_runs?: number
          max_storage_mb?: number
          metadata?: Json
          name?: string
          price_monthly_usd?: number
        }
        Relationships: []
      }
      subscriptions: {
        Row: {
          cancel_at_period_end: boolean
          created_at: string
          current_period_end: string
          current_period_start: string
          id: string
          plan_id: string
          status: Database["billing"]["Enums"]["subscription_status"]
          stripe_customer_id: string | null
          stripe_subscription_id: string | null
          tenant_id: string
          updated_at: string
        }
        Insert: {
          cancel_at_period_end?: boolean
          created_at?: string
          current_period_end?: string
          current_period_start?: string
          id?: string
          plan_id: string
          status?: Database["billing"]["Enums"]["subscription_status"]
          stripe_customer_id?: string | null
          stripe_subscription_id?: string | null
          tenant_id: string
          updated_at?: string
        }
        Update: {
          cancel_at_period_end?: boolean
          created_at?: string
          current_period_end?: string
          current_period_start?: string
          id?: string
          plan_id?: string
          status?: Database["billing"]["Enums"]["subscription_status"]
          stripe_customer_id?: string | null
          stripe_subscription_id?: string | null
          tenant_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "subscriptions_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "plans"
            referencedColumns: ["id"]
          },
        ]
      }
      usage_meters: {
        Row: {
          current_value: number
          id: string
          metric_name: string
          reset_at: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          current_value?: number
          id?: string
          metric_name: string
          reset_at?: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          current_value?: number
          id?: string
          metric_name?: string
          reset_at?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: []
      }
      wallet_transactions: {
        Row: {
          amount_credits: number
          balance_after_credits: number
          created_at: string
          created_by: string | null
          description: string | null
          id: string
          reference_id: string | null
          reference_type: string | null
          tenant_id: string
          tx_type: Database["billing"]["Enums"]["wallet_tx_type"]
          wallet_id: string
        }
        Insert: {
          amount_credits: number
          balance_after_credits: number
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          reference_id?: string | null
          reference_type?: string | null
          tenant_id: string
          tx_type: Database["billing"]["Enums"]["wallet_tx_type"]
          wallet_id: string
        }
        Update: {
          amount_credits?: number
          balance_after_credits?: number
          created_at?: string
          created_by?: string | null
          description?: string | null
          id?: string
          reference_id?: string | null
          reference_type?: string | null
          tenant_id?: string
          tx_type?: Database["billing"]["Enums"]["wallet_tx_type"]
          wallet_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "wallet_transactions_wallet_id_fkey"
            columns: ["wallet_id"]
            isOneToOne: false
            referencedRelation: "wallets"
            referencedColumns: ["id"]
          },
        ]
      }
      wallets: {
        Row: {
          balance_credits: number
          created_at: string
          id: string
          tenant_id: string
          total_spent_credits: number
          total_topped_up_credits: number
          updated_at: string
        }
        Insert: {
          balance_credits?: number
          created_at?: string
          id?: string
          tenant_id: string
          total_spent_credits?: number
          total_topped_up_credits?: number
          updated_at?: string
        }
        Update: {
          balance_credits?: number
          created_at?: string
          id?: string
          tenant_id?: string
          total_spent_credits?: number
          total_topped_up_credits?: number
          updated_at?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      check_tenant_quota: {
        Args: { _increment?: number; _metric_name: string; _tenant_id: string }
        Returns: boolean
      }
      create_payment_intent: {
        Args: {
          _amount_credits: number
          _buyer_email?: string
          _gateway_id: string
          _target_id: string
          _target_type: Database["billing"]["Enums"]["payment_target_type"]
          _tenant_id?: string
        }
        Returns: Json
      }
      credit_tenant_wallet: {
        Args: {
          _amount_credits: number
          _description?: string
          _reference_id?: string
          _reference_type?: string
          _tenant_id: string
          _tx_type?: Database["billing"]["Enums"]["wallet_tx_type"]
        }
        Returns: number
      }
      debit_tenant_wallet: {
        Args: {
          _amount_credits: number
          _description?: string
          _reference_id?: string
          _reference_type?: string
          _tenant_id: string
          _tx_type?: Database["billing"]["Enums"]["wallet_tx_type"]
        }
        Returns: number
      }
      get_active_gateways: {
        Args: never
        Returns: {
          channel: Database["billing"]["Enums"]["payment_channel"]
          currency: string
          driver: string
          id: string
          name: string
          public_config: Json
          rate_per_credit: number
          sort_order: number
        }[]
      }
      get_next_receiving_account: {
        Args: { _amount_vnd?: number }
        Returns: {
          account_name: string
          account_no: string
          bank_bin: string
          bank_name: string
          created_at: string
          current_daily_total: number
          daily_limit_vnd: number
          daily_reset_at: string
          id: string
          is_active: boolean
          metadata: Json
          priority: number
          qr_template: string
          status: string
          updated_at: string
        }
        SetofOptions: {
          from: "*"
          to: "bank_receiving_accounts"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      record_usage: {
        Args: { _increment?: number; _metric_name: string; _tenant_id: string }
        Returns: number
      }
      settle_payment_intent: {
        Args: {
          _actual_pay_amount?: number
          _force_approve?: boolean
          _intent_id?: string
          _provider_tx_id?: string
          _raw_metadata?: Json
          _transfer_code?: string
        }
        Returns: Json
      }
    }
    Enums: {
      payment_channel:
        | "internal_wallet"
        | "bank_transfer"
        | "e_wallet"
        | "card_intl"
        | "crypto"
      payment_intent_status:
        | "pending"
        | "processing"
        | "manual_review"
        | "succeeded"
        | "failed"
        | "expired"
        | "refunded"
      payment_target_type:
        | "wallet_topup"
        | "commerce_order"
        | "subscription_upgrade"
      subscription_status:
        | "free_tier"
        | "trialing"
        | "active"
        | "past_due"
        | "canceled"
        | "unpaid"
      wallet_tx_type:
        | "topup"
        | "purchase"
        | "refund"
        | "admin_adjustment"
        | "bonus"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  events: {
    Tables: {
      deliveries: {
        Row: {
          attempt: number
          created_at: string
          duration_ms: number | null
          event_id: string
          id: string
          response_body: string | null
          status_code: number | null
          subscription_id: string
          tenant_id: string
        }
        Insert: {
          attempt?: number
          created_at?: string
          duration_ms?: number | null
          event_id: string
          id?: string
          response_body?: string | null
          status_code?: number | null
          subscription_id: string
          tenant_id: string
        }
        Update: {
          attempt?: number
          created_at?: string
          duration_ms?: number | null
          event_id?: string
          id?: string
          response_body?: string | null
          status_code?: number | null
          subscription_id?: string
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "deliveries_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "outbox"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deliveries_subscription_id_fkey"
            columns: ["subscription_id"]
            isOneToOne: false
            referencedRelation: "subscriptions"
            referencedColumns: ["id"]
          },
        ]
      }
      outbox: {
        Row: {
          created_at: string
          error_message: string | null
          event_type: string
          id: string
          payload: Json
          processed_at: string | null
          retry_count: number
          status: Database["events"]["Enums"]["outbox_status"]
          tenant_id: string | null
        }
        Insert: {
          created_at?: string
          error_message?: string | null
          event_type: string
          id?: string
          payload?: Json
          processed_at?: string | null
          retry_count?: number
          status?: Database["events"]["Enums"]["outbox_status"]
          tenant_id?: string | null
        }
        Update: {
          created_at?: string
          error_message?: string | null
          event_type?: string
          id?: string
          payload?: Json
          processed_at?: string | null
          retry_count?: number
          status?: Database["events"]["Enums"]["outbox_status"]
          tenant_id?: string | null
        }
        Relationships: []
      }
      subscriptions: {
        Row: {
          created_at: string
          created_by: string | null
          event_types: string[]
          id: string
          is_active: boolean
          secret: string
          target_url: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          event_types?: string[]
          id?: string
          is_active?: boolean
          secret: string
          target_url: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          event_types?: string[]
          id?: string
          is_active?: boolean
          secret?: string
          target_url?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      claim_outbox_batch: {
        Args: { p_batch_size?: number }
        Returns: {
          event_type: string
          id: string
          payload: Json
          retry_count: number
          tenant_id: string
        }[]
      }
      emit_event: {
        Args: { _event_type: string; _payload?: Json; _tenant_id: string }
        Returns: string
      }
    }
    Enums: {
      outbox_status: "pending" | "processing" | "delivered" | "failed"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  media: {
    Tables: {
      assets: {
        Row: {
          bucket_name: string
          created_at: string
          created_by: string | null
          file_path: string
          file_size_bytes: number
          id: string
          metadata: Json
          mime_type: string
          original_name: string
          tenant_id: string
          updated_at: string
        }
        Insert: {
          bucket_name?: string
          created_at?: string
          created_by?: string | null
          file_path: string
          file_size_bytes: number
          id?: string
          metadata?: Json
          mime_type: string
          original_name: string
          tenant_id: string
          updated_at?: string
        }
        Update: {
          bucket_name?: string
          created_at?: string
          created_by?: string | null
          file_path?: string
          file_size_bytes?: number
          id?: string
          metadata?: Json
          mime_type?: string
          original_name?: string
          tenant_id?: string
          updated_at?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      [_ in never]: never
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      audit_logs: {
        Row: {
          action: string
          actor_id: string | null
          created_at: string
          entity_id: string
          entity_type: string
          id: number
          ip_address: unknown
          new_values: Json | null
          old_values: Json | null
          tenant_id: string
          user_agent: string | null
        }
        Insert: {
          action: string
          actor_id?: string | null
          created_at?: string
          entity_id: string
          entity_type: string
          id?: never
          ip_address?: unknown
          new_values?: Json | null
          old_values?: Json | null
          tenant_id: string
          user_agent?: string | null
        }
        Update: {
          action?: string
          actor_id?: string | null
          created_at?: string
          entity_id?: string
          entity_type?: string
          id?: never
          ip_address?: unknown
          new_values?: Json | null
          old_values?: Json | null
          tenant_id?: string
          user_agent?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "audit_logs_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "audit_logs_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      member_roles: {
        Row: {
          assigned_at: string
          member_id: string
          role_id: string
          tenant_id: string
        }
        Insert: {
          assigned_at?: string
          member_id: string
          role_id: string
          tenant_id: string
        }
        Update: {
          assigned_at?: string
          member_id?: string
          role_id?: string
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "member_roles_member_id_fkey"
            columns: ["member_id"]
            isOneToOne: false
            referencedRelation: "tenant_members"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_roles_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "member_roles_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      permissions: {
        Row: {
          created_at: string
          description: string
          id: string
          module: string
        }
        Insert: {
          created_at?: string
          description: string
          id: string
          module: string
        }
        Update: {
          created_at?: string
          description?: string
          id?: string
          module?: string
        }
        Relationships: []
      }
      profiles: {
        Row: {
          avatar_url: string | null
          created_at: string
          email: string
          full_name: string | null
          id: string
          metadata: Json | null
          updated_at: string
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          email: string
          full_name?: string | null
          id: string
          metadata?: Json | null
          updated_at?: string
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          email?: string
          full_name?: string | null
          id?: string
          metadata?: Json | null
          updated_at?: string
        }
        Relationships: []
      }
      role_permissions: {
        Row: {
          granted_at: string
          permission_id: string
          role_id: string
        }
        Insert: {
          granted_at?: string
          permission_id: string
          role_id: string
        }
        Update: {
          granted_at?: string
          permission_id?: string
          role_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "role_permissions_permission_id_fkey"
            columns: ["permission_id"]
            isOneToOne: false
            referencedRelation: "permissions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "role_permissions_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
        ]
      }
      roles: {
        Row: {
          created_at: string
          description: string | null
          display_name: string
          id: string
          is_system: boolean
          name: string
          tenant_id: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          display_name: string
          id?: string
          is_system?: boolean
          name: string
          tenant_id?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          description?: string | null
          display_name?: string
          id?: string
          is_system?: boolean
          name?: string
          tenant_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "roles_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      system_plugins: {
        Row: {
          dependencies: string[]
          description: string | null
          id: string
          installed_at: string
          installed_by: string | null
          is_system: boolean
          metadata: Json
          name: string
          schema_name: string
          status: Database["public"]["Enums"]["plugin_status"]
          version: string
        }
        Insert: {
          dependencies?: string[]
          description?: string | null
          id: string
          installed_at?: string
          installed_by?: string | null
          is_system?: boolean
          metadata?: Json
          name: string
          schema_name: string
          status?: Database["public"]["Enums"]["plugin_status"]
          version?: string
        }
        Update: {
          dependencies?: string[]
          description?: string | null
          id?: string
          installed_at?: string
          installed_by?: string | null
          is_system?: boolean
          metadata?: Json
          name?: string
          schema_name?: string
          status?: Database["public"]["Enums"]["plugin_status"]
          version?: string
        }
        Relationships: [
          {
            foreignKeyName: "system_plugins_installed_by_fkey"
            columns: ["installed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      tenant_invitations: {
        Row: {
          created_at: string
          email: string
          expires_at: string
          id: string
          invited_by: string
          role_id: string
          status: Database["public"]["Enums"]["invitation_status"]
          tenant_id: string
          token_hash: string
        }
        Insert: {
          created_at?: string
          email: string
          expires_at: string
          id?: string
          invited_by: string
          role_id: string
          status?: Database["public"]["Enums"]["invitation_status"]
          tenant_id: string
          token_hash: string
        }
        Update: {
          created_at?: string
          email?: string
          expires_at?: string
          id?: string
          invited_by?: string
          role_id?: string
          status?: Database["public"]["Enums"]["invitation_status"]
          tenant_id?: string
          token_hash?: string
        }
        Relationships: [
          {
            foreignKeyName: "tenant_invitations_invited_by_fkey"
            columns: ["invited_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tenant_invitations_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tenant_invitations_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      tenant_members: {
        Row: {
          id: string
          joined_at: string
          status: Database["public"]["Enums"]["membership_status"]
          tenant_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          id?: string
          joined_at?: string
          status?: Database["public"]["Enums"]["membership_status"]
          tenant_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          id?: string
          joined_at?: string
          status?: Database["public"]["Enums"]["membership_status"]
          tenant_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "tenant_members_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tenant_members_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      tenants: {
        Row: {
          avatar_url: string | null
          created_at: string
          created_by: string | null
          id: string
          metadata: Json | null
          name: string
          slug: string
          status: Database["public"]["Enums"]["tenant_status"]
          updated_at: string
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          metadata?: Json | null
          name: string
          slug: string
          status?: Database["public"]["Enums"]["tenant_status"]
          updated_at?: string
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          metadata?: Json | null
          name?: string
          slug?: string
          status?: Database["public"]["Enums"]["tenant_status"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "tenants_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      accept_invitation: { Args: { p_token: string }; Returns: Json }
      acquire_browser: {
        Args: {
          p_browser_id: string
          p_device_id: string
          p_device_token: string
        }
        Returns: Json
      }
      acquire_browser_profile: {
        Args: {
          p_device_id: string
          p_device_token: string
          p_profile_id: string
        }
        Returns: Json
      }
      create_browser: {
        Args: {
          p_browser_brand?: string
          p_cpu_cores?: number
          p_custom_proxy?: string
          p_fingerprint_seed?: number
          p_locale?: string
          p_name: string
          p_os_platform?: string
          p_proxy_id?: string
          p_ram_gb?: number
          p_tenant_id?: string
          p_timezone?: string
        }
        Returns: Json
      }
      custom_access_token_hook: { Args: { event: Json }; Returns: Json }
      enroll_device: {
        Args: {
          p_capabilities?: Json
          p_cpu_cores?: number
          p_enrollment_token?: string
          p_machine_fingerprint: string
          p_metadata?: Json
          p_name: string
          p_os_info?: string
          p_ram_mb?: number
          p_tenant_id?: string
        }
        Returns: Json
      }
      get_installed_plugins: {
        Args: never
        Returns: {
          dependencies: string[]
          description: string
          id: string
          installed_at: string
          is_system: boolean
          metadata: Json
          name: string
          schema_name: string
          status: Database["public"]["Enums"]["plugin_status"]
          version: string
        }[]
      }
      get_user_tenant_ids: { Args: never; Returns: string[] }
      has_permission: {
        Args: { requested_permission: string }
        Returns: boolean
      }
      has_tenant_permission: {
        Args: { _permission_id: string; _tenant_id: string }
        Returns: boolean
      }
      heartbeat: {
        Args: {
          p_active_jobs?: number
          p_device_id: string
          p_device_token: string
          p_telemetry?: Json
        }
        Returns: Json
      }
      is_platform_admin: { Args: never; Returns: boolean }
      is_tenant_admin: { Args: { _tenant_id: string }; Returns: boolean }
      is_tenant_member: { Args: { _tenant_id: string }; Returns: boolean }
      is_valid_browser_storage_tenant:
        | { Args: { p_tenant_id: string }; Returns: boolean }
        | { Args: { p_tenant_text: string }; Returns: boolean }
      list_browsers: {
        Args: { p_device_id?: string; p_device_token?: string }
        Returns: Json
      }
      reap_stale_browser_locks: {
        Args: { p_stale_interval?: string }
        Returns: number
      }
      register_plugin: {
        Args: {
          p_dependencies?: string[]
          p_description?: string
          p_id: string
          p_is_system?: boolean
          p_metadata?: Json
          p_name: string
          p_schema_name: string
          p_version: string
        }
        Returns: undefined
      }
      release_browser: {
        Args: {
          p_browser_id: string
          p_cookies_count?: number
          p_device_id: string
          p_device_token: string
          p_metadata?: Json
          p_storage_hash?: string
          p_storage_path?: string
          p_storage_size_bytes?: number
        }
        Returns: Json
      }
      release_browser_profile: {
        Args: {
          p_cookies_count?: number
          p_device_id: string
          p_device_token: string
          p_metadata?: Json
          p_profile_id: string
          p_storage_hash?: string
          p_storage_path?: string
          p_storage_size_bytes?: number
        }
        Returns: Json
      }
      resolve_plugin_dependencies: {
        Args: { p_target_plugins: string[] }
        Returns: {
          install_order: number
          is_installed: boolean
          plugin_id: string
          plugin_name: string
          schema_name: string
        }[]
      }
      safe_cast_uuid: { Args: { val: string }; Returns: string }
      unregister_plugin: { Args: { p_id: string }; Returns: undefined }
      upsert_browser_profile: {
        Args: {
          p_cookies_count?: number
          p_cpu_cores?: number
          p_device_id: string
          p_device_pixel_ratio?: number
          p_device_token: string
          p_fingerprint_seed: number
          p_locale?: string
          p_metadata?: Json
          p_name: string
          p_os_platform?: string
          p_profile_id: string
          p_proxy?: string
          p_ram_gb?: number
          p_screen_height?: number
          p_screen_width?: number
          p_storage_hash?: string
          p_storage_path?: string
          p_storage_size_bytes?: number
          p_timezone?: string
        }
        Returns: Json
      }
    }
    Enums: {
      invitation_status: "pending" | "accepted" | "revoked" | "expired"
      membership_status: "active" | "suspended"
      plugin_status: "installed" | "disabled" | "uninstalled"
      tenant_status: "active" | "suspended" | "archived"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  workers: {
    Tables: {
      devices: {
        Row: {
          active_jobs: number
          capabilities: Json
          config_override: Json
          cpu_cores: number
          device_token_hash: string | null
          id: string
          last_heartbeat_at: string | null
          machine_fingerprint: string
          metadata: Json
          name: string
          os_info: string | null
          ram_mb: number
          registered_at: string
          status: Database["workers"]["Enums"]["device_status"]
          telemetry: Json
          tenant_id: string
          updated_at: string
          version: string
        }
        Insert: {
          active_jobs?: number
          capabilities?: Json
          config_override?: Json
          cpu_cores?: number
          device_token_hash?: string | null
          id?: string
          last_heartbeat_at?: string | null
          machine_fingerprint: string
          metadata?: Json
          name: string
          os_info?: string | null
          ram_mb?: number
          registered_at?: string
          status?: Database["workers"]["Enums"]["device_status"]
          telemetry?: Json
          tenant_id: string
          updated_at?: string
          version?: string
        }
        Update: {
          active_jobs?: number
          capabilities?: Json
          config_override?: Json
          cpu_cores?: number
          device_token_hash?: string | null
          id?: string
          last_heartbeat_at?: string | null
          machine_fingerprint?: string
          metadata?: Json
          name?: string
          os_info?: string | null
          ram_mb?: number
          registered_at?: string
          status?: Database["workers"]["Enums"]["device_status"]
          telemetry?: Json
          tenant_id?: string
          updated_at?: string
          version?: string
        }
        Relationships: []
      }
      node_browsers: {
        Row: {
          browser_type: string
          created_at: string
          device_id: string
          executable_path: string | null
          id: string
          is_active: boolean
          last_seen_at: string
          local_profile_id: string
          metadata: Json
          name: string
          tenant_id: string
          user_data_dir: string
        }
        Insert: {
          browser_type?: string
          created_at?: string
          device_id: string
          executable_path?: string | null
          id?: string
          is_active?: boolean
          last_seen_at?: string
          local_profile_id: string
          metadata?: Json
          name: string
          tenant_id: string
          user_data_dir: string
        }
        Update: {
          browser_type?: string
          created_at?: string
          device_id?: string
          executable_path?: string | null
          id?: string
          is_active?: boolean
          last_seen_at?: string
          local_profile_id?: string
          metadata?: Json
          name?: string
          tenant_id?: string
          user_data_dir?: string
        }
        Relationships: [
          {
            foreignKeyName: "fk_workers_node_browsers_device"
            columns: ["tenant_id", "device_id"]
            isOneToOne: false
            referencedRelation: "devices"
            referencedColumns: ["tenant_id", "id"]
          },
        ]
      }
      proxies: {
        Row: {
          city: string | null
          country_code: string | null
          created_at: string
          error_count: number
          host: string
          id: string
          ip_address: unknown
          is_residential: boolean
          last_checked_at: string | null
          latency_ms: number | null
          password_hash: string | null
          port: number
          protocol: string
          status: string
          tags: string[]
          tenant_id: string
          updated_at: string
          username: string | null
        }
        Insert: {
          city?: string | null
          country_code?: string | null
          created_at?: string
          error_count?: number
          host: string
          id?: string
          ip_address?: unknown
          is_residential?: boolean
          last_checked_at?: string | null
          latency_ms?: number | null
          password_hash?: string | null
          port: number
          protocol?: string
          status?: string
          tags?: string[]
          tenant_id: string
          updated_at?: string
          username?: string | null
        }
        Update: {
          city?: string | null
          country_code?: string | null
          created_at?: string
          error_count?: number
          host?: string
          id?: string
          ip_address?: unknown
          is_residential?: boolean
          last_checked_at?: string | null
          latency_ms?: number | null
          password_hash?: string | null
          port?: number
          protocol?: string
          status?: string
          tags?: string[]
          tenant_id?: string
          updated_at?: string
          username?: string | null
        }
        Relationships: []
      }
    }
    Views: {
      browsers: {
        Row: {
          accept_languages: string | null
          browser_brand: string | null
          browser_type: string | null
          cookies_count: number | null
          cpu_cores: number | null
          created_at: string | null
          custom_proxy: string | null
          device_pixel_ratio: number | null
          engine_version: string | null
          extensions: Json | null
          fingerprint_seed: number | null
          group_name: string | null
          id: string | null
          last_launched_at: string | null
          last_synced_at: string | null
          locale: string | null
          locked_at: string | null
          locked_by_device_id: string | null
          metadata: Json | null
          name: string | null
          os_platform: string | null
          os_version: string | null
          proxy_id: string | null
          ram_gb: number | null
          screen_height: number | null
          screen_width: number | null
          sec_ch_ua: string | null
          sec_ch_ua_mobile: boolean | null
          sec_ch_ua_platform: string | null
          startup_flags: Json | null
          status: string | null
          storage_hash: string | null
          storage_path: string | null
          storage_size_bytes: number | null
          tags: string[] | null
          tenant_id: string | null
          timezone: string | null
          updated_at: string | null
          user_agent: string | null
          webrtc_mode: string | null
        }
        Insert: {
          accept_languages?: string | null
          browser_brand?: string | null
          browser_type?: string | null
          cookies_count?: number | null
          cpu_cores?: number | null
          created_at?: string | null
          custom_proxy?: string | null
          device_pixel_ratio?: number | null
          engine_version?: string | null
          extensions?: Json | null
          fingerprint_seed?: number | null
          group_name?: string | null
          id?: string | null
          last_launched_at?: string | null
          last_synced_at?: string | null
          locale?: string | null
          locked_at?: string | null
          locked_by_device_id?: string | null
          metadata?: Json | null
          name?: string | null
          os_platform?: string | null
          os_version?: string | null
          proxy_id?: string | null
          ram_gb?: number | null
          screen_height?: number | null
          screen_width?: number | null
          sec_ch_ua?: string | null
          sec_ch_ua_mobile?: boolean | null
          sec_ch_ua_platform?: string | null
          startup_flags?: Json | null
          status?: string | null
          storage_hash?: string | null
          storage_path?: string | null
          storage_size_bytes?: number | null
          tags?: string[] | null
          tenant_id?: string | null
          timezone?: string | null
          updated_at?: string | null
          user_agent?: string | null
          webrtc_mode?: string | null
        }
        Update: {
          accept_languages?: string | null
          browser_brand?: string | null
          browser_type?: string | null
          cookies_count?: number | null
          cpu_cores?: number | null
          created_at?: string | null
          custom_proxy?: string | null
          device_pixel_ratio?: number | null
          engine_version?: string | null
          extensions?: Json | null
          fingerprint_seed?: number | null
          group_name?: string | null
          id?: string | null
          last_launched_at?: string | null
          last_synced_at?: string | null
          locale?: string | null
          locked_at?: string | null
          locked_by_device_id?: string | null
          metadata?: Json | null
          name?: string | null
          os_platform?: string | null
          os_version?: string | null
          proxy_id?: string | null
          ram_gb?: number | null
          screen_height?: number | null
          screen_width?: number | null
          sec_ch_ua?: string | null
          sec_ch_ua_mobile?: boolean | null
          sec_ch_ua_platform?: string | null
          startup_flags?: Json | null
          status?: string | null
          storage_hash?: string | null
          storage_path?: string | null
          storage_size_bytes?: number | null
          tags?: string[] | null
          tenant_id?: string | null
          timezone?: string | null
          updated_at?: string | null
          user_agent?: string | null
          webrtc_mode?: string | null
        }
        Relationships: []
      }
    }
    Functions: {
      acquire_browser: {
        Args: {
          p_browser_id: string
          p_device_id: string
          p_device_token: string
        }
        Returns: Json
      }
      create_browser: {
        Args: {
          p_browser_brand?: string
          p_cpu_cores?: number
          p_custom_proxy?: string
          p_fingerprint_seed?: number
          p_locale?: string
          p_name: string
          p_os_platform?: string
          p_proxy_id?: string
          p_ram_gb?: number
          p_tenant_id?: string
          p_timezone?: string
        }
        Returns: Json
      }
      enroll_device: {
        Args: {
          p_capabilities?: Json
          p_cpu_cores?: number
          p_enrollment_token?: string
          p_machine_fingerprint: string
          p_metadata?: Json
          p_name: string
          p_os_info?: string
          p_ram_mb?: number
          p_tenant_id?: string
        }
        Returns: Json
      }
      heartbeat: {
        Args: {
          p_active_jobs?: number
          p_device_id: string
          p_device_token: string
          p_telemetry?: Json
        }
        Returns: Json
      }
      list_browsers: {
        Args: { p_device_id?: string; p_device_token?: string }
        Returns: Json
      }
      reap_stale_browser_locks: {
        Args: { p_stale_interval?: string }
        Returns: {
          browser_name: string
          dead_device_id: string
          reaped_browser_id: string
          tenant_id: string
        }[]
      }
      release_browser: {
        Args: {
          p_browser_id: string
          p_cookies_count?: number
          p_device_id: string
          p_device_token: string
          p_metadata?: Json
          p_storage_hash?: string
          p_storage_path?: string
          p_storage_size_bytes?: number
        }
        Returns: Json
      }
    }
    Enums: {
      device_status: "offline" | "idle" | "busy" | "maintenance" | "disabled"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  automation: {
    Enums: {
      job_status: [
        "pending",
        "queued",
        "running",
        "paused",
        "completed",
        "failed",
        "cancelled",
      ],
      log_level: ["trace", "debug", "info", "warn", "error", "fatal"],
      workflow_status: ["draft", "published", "archived"],
    },
  },
  billing: {
    Enums: {
      payment_channel: [
        "internal_wallet",
        "bank_transfer",
        "e_wallet",
        "card_intl",
        "crypto",
      ],
      payment_intent_status: [
        "pending",
        "processing",
        "manual_review",
        "succeeded",
        "failed",
        "expired",
        "refunded",
      ],
      payment_target_type: [
        "wallet_topup",
        "commerce_order",
        "subscription_upgrade",
      ],
      subscription_status: [
        "free_tier",
        "trialing",
        "active",
        "past_due",
        "canceled",
        "unpaid",
      ],
      wallet_tx_type: [
        "topup",
        "purchase",
        "refund",
        "admin_adjustment",
        "bonus",
      ],
    },
  },
  events: {
    Enums: {
      outbox_status: ["pending", "processing", "delivered", "failed"],
    },
  },
  media: {
    Enums: {},
  },
  public: {
    Enums: {
      invitation_status: ["pending", "accepted", "revoked", "expired"],
      membership_status: ["active", "suspended"],
      plugin_status: ["installed", "disabled", "uninstalled"],
      tenant_status: ["active", "suspended", "archived"],
    },
  },
  workers: {
    Enums: {
      device_status: ["offline", "idle", "busy", "maintenance", "disabled"],
    },
  },
} as const
