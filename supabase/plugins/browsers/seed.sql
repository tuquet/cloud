-- ============================================================================
-- TUQUET-CLOUD PLUGIN: BROWSERS SEED DATA
-- Description: Seeds releases and templates
-- ============================================================================

INSERT INTO browsers.releases (version, major_version, channel, os_platform, arch, download_url, sha256_checksum, file_size_bytes, is_recommended, release_notes)
VALUES 
    (
        '148.0.7778.215', 148, 'stable', 'windows', 'x86_64',
        'https://storage.tuquet.com/engines/chromium-148.0.7778.215-win64.zip',
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        185400000, true, 'Official Chromium 148 stable build for Windows 64-bit'
    ),
    (
        '148.0.7778.215', 148, 'stable', 'macos', 'aarch64',
        'https://storage.tuquet.com/engines/chromium-148.0.7778.215-mac-arm64.zip',
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        172000000, true, 'Official Chromium 148 stable build for macOS Apple Silicon'
    ),
    (
        '148.0.7778.215', 148, 'stable', 'linux', 'x86_64',
        'https://storage.tuquet.com/engines/chromium-148.0.7778.215-linux64.tar.gz',
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        198000000, true, 'Official Chromium 148 stable build for Linux x86_64'
    )
ON CONFLICT (version, channel, os_platform, arch) DO NOTHING;
