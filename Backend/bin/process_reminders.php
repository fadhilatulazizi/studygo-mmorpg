<?php
declare(strict_types=1);
require dirname(__DIR__).'/src/bootstrap.php';

$pdo->beginTransaction();
try {
    $q=$pdo->query("SELECT id,user_id,title,message FROM study_reminders WHERE status='pending' AND remind_at<=UTC_TIMESTAMP() ORDER BY remind_at LIMIT 200 FOR UPDATE");
    $rows=$q->fetchAll();
    $insert=$pdo->prepare("INSERT INTO study_notifications(user_id,title,body,notification_type,data_json) VALUES(?,?,?,'reminder',?)");
    $update=$pdo->prepare("UPDATE study_reminders SET status='sent' WHERE id=? AND status='pending'");
    foreach($rows as $row){
        $insert->execute([$row['user_id'],$row['title'],$row['message']??'Pengingat belajar Anda sudah waktunya.',json_encode(['reminderId'=>(int)$row['id']])]);
        $update->execute([$row['id']]);
    }
    $pdo->commit();
    fwrite(STDOUT,'Processed '.count($rows)." reminders\n");
} catch(Throwable $e) {
    if($pdo->inTransaction())$pdo->rollBack();
    error_log($e->getMessage());fwrite(STDERR,"Reminder worker failed\n");exit(1);
}
