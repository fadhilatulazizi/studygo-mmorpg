<?php
declare(strict_types=1);

return [
    'app' => [
        'env' => getenv('APP_ENV') ?: 'production',
        'debug' => filter_var(getenv('APP_DEBUG') ?: '0', FILTER_VALIDATE_BOOL),
        'allowed_origins' => array_values(array_filter(array_map('trim', explode(',', getenv('CORS_ALLOWED_ORIGINS') ?: '')))),
    ],
    'database' => [
        'dsn' => getenv('DB_DSN') ?: 'mysql:host=127.0.0.1;dbname=studygo;charset=utf8mb4',
        'username' => getenv('DB_USERNAME') ?: 'studygo_user',
        'password' => getenv('DB_PASSWORD') ?: '',
    ],
    'auth' => [
        'access_ttl' => 900,
        'refresh_ttl_days' => 30,
    ],
    'ai' => [
        'provider' => getenv('AI_PROVIDER') ?: 'gemini',
        'model' => getenv('AI_MODEL') ?: 'gemini-2.5-flash',
        'gemini_api_key' => getenv('GEMINI_API_KEY') ?: '',
        'openai_api_key' => getenv('OPENAI_API_KEY') ?: '',
    ],
    'ads' => [
        'callback_secret' => getenv('AD_REWARD_CALLBACK_SECRET') ?: '',
    ],
    'game_jwt' => [
        'secret' => getenv('GAME_JWT_SECRET') ?: '',
        'issuer' => getenv('GAME_JWT_ISSUER') ?: 'https://api.studygo.example',
        'audience' => getenv('GAME_JWT_AUDIENCE') ?: 'studygo-mmorpg',
        'ttl' => 900,
    ],
];
