<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

http_response_code(200);
echo json_encode([
    'ok' => true,
    'service' => 'studygo-game-api',
    'status' => 'scaffold',
], JSON_UNESCAPED_SLASHES);
