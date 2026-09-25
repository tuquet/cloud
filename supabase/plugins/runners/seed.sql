-- ============================================================================
-- TUQUET-CLOUD PLUGIN: RUNNERS (SEED DATA)
-- Description: Realistic initial data for testing runner devices
-- ============================================================================

INSERT INTO runners.devices (
    id, tenant_id, name, machine_fingerprint, status, version, os_info,
    cpu_cores, ram_mb, capabilities, last_heartbeat_at
)
VALUES
    (
        'd0000000-0000-0000-0000-000000000001',
        'b0000000-0000-0000-0000-000000000001',
        'Workstation-Dev-Node-01',
        'HWID-WIN-8942-X86',
        'idle',
        '0.1.0',
        'Windows 11 Pro 64-bit',
        8,
        16384,
        '["agent:claude-agy", "shell:pwsh", "browser:automa"]'::jsonb,
        now()
    ),
    (
        'd0000000-0000-0000-0000-000000000002',
        'b0000000-0000-0000-0000-000000000001',
        'Cloud-VPS-Worker-SG',
        'HWID-LNX-2201-SG',
        'busy',
        '0.1.0',
        'Ubuntu 22.04 LTS x86_64',
        16,
        32768,
        '["agent:claude-agy", "shell:bash", "http"]'::jsonb,
        now()
    )
ON CONFLICT (tenant_id, machine_fingerprint) DO UPDATE SET
    status = EXCLUDED.status,
    last_heartbeat_at = EXCLUDED.last_heartbeat_at;
