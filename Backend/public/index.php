<?php
declare(strict_types=1);

use StudyGo\Http\ApiKernel;

require dirname(__DIR__) . '/src/bootstrap.php';

$kernel = new ApiKernel($config, $pdo);
$kernel->handle();
