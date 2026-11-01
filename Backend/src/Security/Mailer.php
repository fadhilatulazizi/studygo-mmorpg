<?php
declare(strict_types=1);
namespace StudyGo\Security;

final class Mailer
{
    public function __construct(private array $config) {}
    public function send(string $to,string $subject,string $html): bool
    {
        $mail=$this->config['mail']??[];
        $from=(string)($mail['from_address']??'');
        if(!filter_var($from,FILTER_VALIDATE_EMAIL)||!filter_var($to,FILTER_VALIDATE_EMAIL)) return false;
        $name=str_replace(["\r","\n",'"'], '', (string)($mail['from_name']??'StudyGo'));
        $headers="MIME-Version: 1.0\r\nContent-Type: text/html; charset=UTF-8\r\n";
        $headers.='From: "'.$name.'" <'.$from.">\r\n";
        return @mail($to,'=?UTF-8?B?'.base64_encode($subject).'?=',$html,$headers);
    }
}
