-- ============================================================================
-- TUQUET-CLOUD PLUGIN: BROWSERS SEED DATA
-- Description: Seeds authentic releases from adryfish/fingerprint-chromium
-- ============================================================================

INSERT INTO browsers.releases (
    version, tag, channel, status, os_platform, arch,
    asset_name, download_url, file_size_bytes, is_recommended, notes, published_at
)
VALUES 
    -- 148.0.7778.215 (Golden LTS)
    (
        '148.0.7778.215', '148.0.7778.215', 'lts', 'recommended', 'windows', 'x86_64',
        'ungoogled-chromium_148.0.7778.215-1.1_windows_x64.zip',
        'https://github.com/adryfish/fingerprint-chromium/releases/download/148.0.7778.215/ungoogled-chromium_148.0.7778.215-1.1_windows_x64.zip',
        189767686, true,
        'Golden LTS Release: Zero canvas readback crashes, realistic WebGL GPU parameter simulation, randomized 8/16/32 GB device memory.',
        '2026-06-21T04:34:00Z'
    ),
    (
        '148.0.7778.215', '148.0.7778.215', 'lts', 'recommended', 'linux', 'x86_64',
        'ungoogled-chromium-148.0.7778.215-1-x86_64_linux.tar.xz',
        'https://github.com/adryfish/fingerprint-chromium/releases/download/148.0.7778.215/ungoogled-chromium-148.0.7778.215-1-x86_64_linux.tar.xz',
        141269020, true,
        'Golden LTS Release: Zero canvas readback crashes, realistic WebGL GPU parameter simulation, randomized 8/16/32 GB device memory.',
        '2026-06-21T04:34:00Z'
    ),
    (
        '148.0.7778.215', '148.0.7778.215', 'lts', 'recommended', 'macos', 'x86_64',
        'ungoogled-chromium_148.0.7778.215-1.1_macos.dmg',
        'https://github.com/adryfish/fingerprint-chromium/releases/download/148.0.7778.215/ungoogled-chromium_148.0.7778.215-1.1_macos.dmg',
        140187500, true,
        'Golden LTS Release: Zero canvas readback crashes, realistic WebGL GPU parameter simulation, randomized 8/16/32 GB device memory.',
        '2026-06-21T04:34:00Z'
    ),
    -- 150.0.7871.186 (Latest - Buggy)
    (
        '150.0.7871.186', '150.0.7871.186', 'latest', 'buggy', 'windows', 'x86_64',
        'ungoogled-chromium_150.0.7871.186-1.1_windows_x64.zip',
        'https://github.com/adryfish/fingerprint-chromium/releases/download/150.0.7871.186/ungoogled-chromium_150.0.7871.186-1.1_windows_x64.zip',
        193743241, false,
        'Upstream regression: SIGSEGV / Crashpad_NotConnectedToHandler in getImageData() / readPixels() (Issues #94 & #95). Not recommended for production.',
        '2026-10-02T14:02:29Z'
    ),
    -- 144.0.7559.132 (Archive - Deprecated)
    (
        '144.0.7559.132', '144.0.7559.132', 'archive', 'deprecated', 'windows', 'x86_64',
        'ungoogled-chromium_144.0.7559.132-1.1_windows_x64.zip',
        'https://github.com/adryfish/fingerprint-chromium/releases/download/144.0.7559.132/ungoogled-chromium_144.0.7559.132-1.1_windows_x64.zip',
        176796270, false,
        'Introduced realistic WebGL parameter simulation. Deprecated manual --fingerprint-gpu-vendor.',
        '2026-02-27T09:02:24Z'
    )
ON CONFLICT (version, channel, os_platform, arch) DO NOTHING;
