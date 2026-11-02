<?php
declare(strict_types=1);

/**
 * One-time StudyGo cPanel installer.
 * Deploy temporarily as public/install.php. Remove it after installation.
 */
session_start();
header('X-Content-Type-Options: nosniff');
header('Cache-Control: no-store');

$backendRoot = dirname(__DIR__);
$configFile = $backendRoot . '/config/config.php';
$lockFile = $backendRoot . '/config/installed.lock';
$migrationDir = $backendRoot . '/database';
$publicHost = (string)($_SERVER['HTTP_HOST'] ?? '');
$isHttps = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off')
    || (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https');

if (is_file($configFile) || is_file($lockFile)) {
    http_response_code(403);
    exit('StudyGo installer is locked. Remove this installer file from public/; do not delete the lock/config to reinstall.');
}
if (!$isHttps && !in_array($publicHost, ['localhost', '127.0.0.1'], true)) {
    http_response_code(400);
    exit('HTTPS is required to run the installer.');
}
if (!isset($_SESSION['studygo_install_csrf'])) {
    $_SESSION['studygo_install_csrf'] = bin2hex(random_bytes(32));
}
$errors = [];
$done = false;
$step = 'form';

function h(string $v): string { return htmlspecialchars($v, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'); }
function runSqlFile(mysqli $db, string $file): void {
    $sql = file_get_contents($file);
    if ($sql === false || trim($sql) === '') throw new RuntimeException('Cannot read SQL migration: ' . basename($file));
    if (!$db->multi_query($sql)) throw new RuntimeException(basename($file) . ': ' . $db->error);
    do {
        if ($result = $db->store_result()) $result->free();
        if ($db->errno) throw new RuntimeException(basename($file) . ': ' . $db->error);
    } while ($db->more_results() && $db->next_result());
    if ($db->errno) throw new RuntimeException(basename($file) . ': ' . $db->error);
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!hash_equals($_SESSION['studygo_install_csrf'], (string)($_POST['csrf'] ?? ''))) {
        $errors[] = 'Sesi installer tidak valid. Muat ulang halaman.';
    } else {
        $host = trim((string)($_POST['db_host'] ?? 'localhost'));
        $name = trim((string)($_POST['db_name'] ?? ''));
        $user = trim((string)($_POST['db_user'] ?? ''));
        $pass = (string)($_POST['db_pass'] ?? '');
        $aiProvider = (string)($_POST['ai_provider'] ?? 'gemini');
        $aiModel = trim((string)($_POST['ai_model'] ?? 'gemini-2.5-flash'));
        $aiKey = trim((string)($_POST['ai_key'] ?? ''));
        $mailFrom = trim((string)($_POST['mail_from'] ?? ''));
        $mailAction = trim((string)($_POST['mail_action_url'] ?? ''));
        $uploadDir = trim((string)($_POST['upload_dir'] ?? dirname($backendRoot) . '/studygo-private-uploads'));
        if ($host === '' || $name === '' || $user === '') $errors[] = 'Host, nama database, dan user database wajib diisi.';
        if (!preg_match('/^[A-Za-z0-9_$-]{1,64}$/', $name) || !preg_match('/^[A-Za-z0-9_$-]{1,64}$/', $user)) $errors[] = 'Format nama database/user tidak valid.';
        if (!in_array($aiProvider, ['gemini', 'openai'], true)) $errors[] = 'Provider AI tidak valid.';
        if ($uploadDir === '' || str_starts_with($uploadDir, rtrim($_SERVER['DOCUMENT_ROOT'] ?? '', '/') . '/')) $errors[] = 'Folder upload harus berada di luar document root.';
        if (!$errors) {
            mysqli_report(MYSQLI_REPORT_OFF);
            $db = @new mysqli($host, $user, $pass, $name);
            if ($db->connect_errno) {
                $errors[] = 'Koneksi database gagal. Periksa host, nama database, user, password, dan hak akses.';
            } else {
                $db->set_charset('utf8mb4');
                $files = [
                    $migrationDir . '/migrations/001_world_map.sql',
                    $migrationDir . '/migrations/000_studygo_auth.sql',
                    $migrationDir . '/schema.sql',
                    $migrationDir . '/migrations/002_player_castles.sql',
                    $migrationDir . '/migrations/003_resource_monster_spawns.sql',
                    $migrationDir . '/migrations/004_march_system.sql',
                    $migrationDir . '/migrations/005_march_settlement_recall.sql',
                    $migrationDir . '/migrations/006_studygo_education.sql',
                    $migrationDir . '/migrations/007_auth_security.sql',
                    $migrationDir . '/migrations/008_admob_admin.sql',
                    $migrationDir . '/migrations/009_education_platform.sql',
                    $migrationDir . '/migrations/010_guest_first.sql',
                ];
                try {
                    $db->query("CREATE TABLE IF NOT EXISTS studygo_installer_migrations (migration VARCHAR(190) NOT NULL PRIMARY KEY, applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB");
                    foreach ($files as $file) {
                        if (!is_file($file)) throw new RuntimeException('File migration tidak ditemukan: ' . basename($file));
                        $migration = basename($file);
                        $q = $db->prepare('SELECT migration FROM studygo_installer_migrations WHERE migration=?');
                        $q->bind_param('s', $migration); $q->execute(); $q->store_result();
                        $already = $q->num_rows > 0; $q->close();
                        if ($already) continue;
                        runSqlFile($db, $file);
                        $q = $db->prepare('INSERT INTO studygo_installer_migrations(migration) VALUES(?)');
                        $q->bind_param('s', $migration); $q->execute(); $q->close();
                    }
                    if (!is_dir(dirname($configFile)) && !mkdir(dirname($configFile), 0750, true) && !is_dir(dirname($configFile))) throw new RuntimeException('Tidak dapat membuat folder config.');
                    if (!is_dir($uploadDir) && !mkdir($uploadDir, 0750, true) && !is_dir($uploadDir)) throw new RuntimeException('Tidak dapat membuat folder upload privat.');
                    $config = [
                        'app' => ['env'=>'production','debug'=>false,'allowed_origins'=>[]],
                        'database' => ['dsn'=>'mysql:host='.$host.';dbname='.$name.';charset=utf8mb4','username'=>$user,'password'=>$pass],
                        'auth' => ['access_ttl'=>900,'refresh_ttl_days'=>30,'require_email_verification'=>false],
                        'mail' => ['from_address'=>$mailFrom,'from_name'=>'StudyGo','action_url'=>$mailAction],
                        'ai' => ['provider'=>$aiProvider,'model'=>$aiModel,'gemini_api_key'=>$aiProvider==='gemini'?$aiKey:'','openai_api_key'=>$aiProvider==='openai'?$aiKey:''],
                        'uploads' => ['directory'=>$uploadDir,'max_bytes'=>52428800],
                        'ads' => ['callback_secret'=>bin2hex(random_bytes(32))],
                        'game_jwt' => ['secret'=>bin2hex(random_bytes(32)),'issuer'=>'https://api.studygo.turaja.id','audience'=>'studygo-mmorpg','ttl'=>900],
                    ];
                    $php = "<?php\ndeclare(strict_types=1);\n\nreturn " . var_export($config, true) . ";\n";
                    $tmp = $configFile . '.tmp';
                    if (file_put_contents($tmp, $php, LOCK_EX) === false || !rename($tmp, $configFile)) throw new RuntimeException('Gagal menyimpan config. Periksa izin folder config.');
                    file_put_contents($lockFile, "Installed " . gmdate('c') . "\n", LOCK_EX);
                    $done = true; $step = 'done';
                } catch (Throwable $e) {
                    error_log('StudyGo installer: ' . $e->getMessage());
                    $errors[] = 'Instalasi terhenti pada proses database atau konfigurasi. Periksa error log hosting. Jangan jalankan ulang sebelum status tabel diperiksa.';
                }
                $db->close();
            }
        }
    }
}
?>
<!doctype html>
<html lang="id">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>StudyGo Backend Installer</title>
<style>
:root{color-scheme:light;font-family:system-ui,-apple-system,Segoe UI,sans-serif;background:#f3f6f8;color:#172b35}
*{box-sizing:border-box}body{margin:0;padding:24px}.wrap{max-width:720px;margin:4vh auto;background:#fff;border:1px solid #dce5e8;border-radius:18px;padding:28px;box-shadow:0 12px 36px #102a3810}
h1{margin:0 0 8px;font-size:26px}p{color:#53656e;line-height:1.55}.tag{display:inline-block;background:#e5f4f1;color:#087c70;padding:5px 10px;border-radius:99px;font-size:12px;font-weight:700}
fieldset{border:1px solid #e1e8eb;border-radius:12px;margin:18px 0;padding:16px}legend{font-weight:700;padding:0 6px}label{display:block;font-size:13px;font-weight:650;margin:12px 0 5px}input,select{width:100%;padding:11px;border:1px solid #cbd7dc;border-radius:8px;font:inherit;background:white}button{width:100%;padding:13px;border:0;border-radius:9px;background:#0d9488;color:white;font-weight:750;font-size:15px;margin-top:14px}.err{background:#fff0ee;color:#a42c20;padding:12px;border-radius:9px;margin:12px 0}.ok{background:#eaf8ef;color:#17663a;padding:14px;border-radius:9px}.small{font-size:12px}.warn{border-left:4px solid #e5a000;background:#fff8e6;padding:12px;border-radius:6px;color:#694b00}
</style></head><body><main class="wrap">
<span class="tag">STUDYGO · ONE-TIME SETUP</span><h1>Backend Installation Wizard</h1>
<p>Wizard ini menghubungkan MySQL, menjalankan skema/migrasi backend, lalu membuat konfigurasi produksi secara privat.</p>
<?php foreach($errors as $error): ?><div class="err"><?=h($error)?></div><?php endforeach; ?>
<?php if($done): ?>
<div class="ok"><strong>Instalasi backend selesai.</strong><br>Konfigurasi tersimpan di luar public web root dan migrasi database telah diproses.</div>
<div class="warn"><strong>Langkah keamanan wajib:</strong> hapus file <code>public/install.php</code> sekarang melalui File Manager. Jangan biarkan installer berada di server. Setelah dihapus, buka <code>https://api.studygo.turaja.id/health</code>.</div>
<p>Setelah health check berhasil, lanjutkan tes register/login dan konfigurasi SMTP. Guest session belum termasuk dalam installer ini.</p>
<?php else: ?>
<div class="warn">Jalankan hanya sekali melalui HTTPS pada subdomain API. Gunakan database kosong khusus StudyGo. Jika proses migrasi gagal, jangan klik ulang; periksa error log dan status tabel terlebih dahulu.</div>
<form method="post" autocomplete="off">
<input type="hidden" name="csrf" value="<?=h($_SESSION['studygo_install_csrf'])?>">
<fieldset><legend>1. Database MySQL</legend>
<label>Database host</label><input name="db_host" value="<?=h((string)($_POST['db_host']??'localhost'))?>" required>
<label>Nama database (termasuk prefix cPanel)</label><input name="db_name" value="<?=h((string)($_POST['db_name']??''))?>" required>
<label>User database (termasuk prefix cPanel)</label><input name="db_user" value="<?=h((string)($_POST['db_user']??''))?>" required>
<label>Password database</label><input type="password" name="db_pass" required>
</fieldset>
<fieldset><legend>2. AI Tutor</legend>
<label>Provider</label><select name="ai_provider"><option value="gemini">Google Gemini</option><option value="openai">OpenAI</option></select>
<label>Model</label><input name="ai_model" value="gemini-2.5-flash" required>
<label>API key provider</label><input type="password" name="ai_key" placeholder="Masukkan API key secara langsung di halaman HTTPS">
<p class="small">Key disimpan pada config.php privat, bukan di database atau repository.</p>
</fieldset>
<fieldset><legend>3. Email dan penyimpanan</legend>
<label>Email pengirim (opsional, dapat diatur nanti)</label><input type="email" name="mail_from" placeholder="noreply@studygo.turaja.id">
<label>URL halaman frontend verifikasi/reset (opsional)</label><input type="url" name="mail_action_url" placeholder="https://studygo.turaja.id">
<label>Folder upload privat (di luar document root)</label><input name="upload_dir" value="<?=h((string)($_POST['upload_dir']??dirname($backendRoot).'/studygo-private-uploads'))?>" required>
</fieldset>
<button type="submit">Uji koneksi & instal backend</button>
</form>
<?php endif; ?>
<p class="small">StudyGo Backend Installer · PHP 8.1+ · Installer mengunci dirinya setelah config berhasil dibuat.</p>
</main></body></html>
