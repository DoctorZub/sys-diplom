# Дипломная работа по профессии «Системный администратор»
## Автор: Зубков Данил Андреевич
---
# Содержание
- [Введение](#введение)
- [Настройка Terraform и Yandex Cloud](#настройка-terraform-и-yandex-cloud)
- [Инфраструктура](#инфраструктура)
- [Сеть](#сеть)
- [Мониторинг(Zabbix)](#мониторингzabbix)
- [Сбор логов(ELK)](#сбор-логовelk)
- [Резервное копирование](#резервное-копирование)
- [Заключение](#заключение)
---

### Введение
Ключевая задача данной работы — это разработать отказоустойчивую инфраструктуру для сайта, включающую мониторинг, сбор логов и резервное копирование основных данных. Вся инфраструктура размещается в Yandex Cloud. В качестве тестового сайта выступает приветственная страница сервера Nginx, для мониторинга использутеся Zabbix Server и Zabbix Agents2, для сбора и анализа логов используется ELK стек, в качестве технологии резервного копирования выбрано создание snapshot'ов дисков всех ВМ.  

Весь Terraform и Ansible код, а также конфиги отдельных сервисов размещены в [данном репозитории](https://github.com/DoctorZub/sys-diplom/tree/main/main). 

---
### Настройка Terraform и Yandex Cloud
Перед началом работы с облаком необходимо организовать связь между Terraform и самим облаком, в нашем случае, с Yandex Cloud. Способов получения данных для аутентификации в облаке существует несколько, в данной работе используется метод с сервисным аккаунтом и авторизованным ключом.

В облачной консоли был создан сервисный аккаунт с именем *terraform*, и выпущен авторизованный ключ. 
![Сервисный аккаунт](https://github.com/DoctorZub/sys-diplom/blob/main/main/img/auth_key.png)

Для корректной работы Terraform с Yandex Cloud авторизованный ключ должен располагаться в домашнем каталоге на рабочей станции администратора, т.е. на машине откуда будет инициализитоваться и запускать код Terraform.  
Путь к ключу указывается в файле [providers.tf](https://github.com/DoctorZub/sys-diplom/blob/main/main/providers.tf) в блоке:  
```terraform
provider "yandex" {
  cloud_id                 = var.cloud_id
  folder_id                = var.folder_id
  service_account_key_file = file("~/.authorized_key.json")
}
```
`cloud_id` - идентификатор рабочего облака;  
`folder_id` - идентификатор рабочей директории в облаке;  
Данные поля заполняются через переменные, указанные в файле [variables.tf](https://github.com/DoctorZub/sys-diplom/blob/main/main/variables.tf)

На этом настройка Terraform и Yandex Cloud завершена.

---
### Инфраструктура
Вся инфраструктура состоит из 7-ми виртуальных машин(ВМ) и 1-го балансироващика нагрузки - Application load balancer(ALB):  
- 2 ВМ *(web-a, web-b)* с сервером Nginx, на котором располагается сайт;
- 1 ВМ *(bastion)* - бастион-сервер, выступающих входной точкой для подключения по ssh ко всей инфраструктуре. Конфигурирование всех ВМ осуществляется с рабочей станции администратора по ssh(порт :22) через бастион сервер;
- 1 ВМ *(zabbix)*- Zabbix-server для мониторинга серверов *web-a и web-b*;
- 1 ВМ *(logstash)* - сервер с Logstash для получения и обработки логов серверов Nginx от filebeat;
- 1 ВМ *(elastic)*- сервер с Elasticsearch для хранения логов серверов Nginx;
- 1 ВМ *(kibana)* - сервер с Kibana для визуального представления и анализа информации с Elasticsearch;
- ALB, настроенный на балансировку трафика между серверами *web-a и web-b*.

Terraform код по созданию ВМ описан в файле [vms.tf](https://github.com/DoctorZub/sys-diplom/blob/main/main/vms.tf)

<ins>*web-a, web-b, bastion, zabbix* имеют конфигурацию:</ins>
- vCPU: 2 ядра 20% Intel ice lake;
- RAM: 1 Гб;
- HDD: 10 Гб.
- Сетевой интерфейс: 1 шт.

<ins>Виртуальные машины со стеком ELK имеют конфигурацию немного мощнее, из-за высоких системных требований данных сервисов.</ins>

<ins>*elastic, logstash*:</ins>
- vCPU: 4 ядра 20% Intel ice lake;
- RAM: 8 Гб;
- HDD: 10 Гб.
- Сетевой интерфейс: 1 шт.
  
<ins>*kibana*:</ins>
- vCPU: 2 ядра 20% Intel ice lake;
- RAM: 4 Гб;
- HDD: 10 Гб.
- Сетевой интерфейс: 1 шт.

При создании ВМ в блоке:
```terraform
 metadata = {
    user-data          = file("./cloud-init.yml")
    serial-port-enable = 1
  }
```
указывается ссылка на файл [cloud-init.yml](https://github.com/DoctorZub/sys-diplom/blob/main/main/cloud-init.yml), в котором описывается создание пользователей для ВМ. В данном конкретном случае для каждой машины создается пользователь *user*(без пароля), имеющий права администратора. В этом же файле в поле ` ssh_authorized_keys` указывается публичный ssh ключ рабочей станции, с которой будет происходить подключение по ssh к ВМ и их конфигурирование.

Создание балансировщика Application load balancer описано в файле [ALB.tf](https://github.com/DoctorZub/sys-diplom/blob/main/main/ALB.tf)  
Вкратце, порядок создания ALB:
1. Создается `target-group` *tg-alb*, в которой в качестве целей(targets) указываются сервера *web-a и web-b*;
2. Далее создается `backend-group` *backend1* и настраивается на 80 порт ранее созданной `target-group`. Также настраивается healthcheck, направленный на 80 порт и путь /, привязанной целевой группы *tg-alb*.
3. Следующим шагом идет создание `Virtual Host` *vh1* и  `HTTP-router` *http-router1*. К *vh1* подключается *http-router1*, и настраивается маршрут по перенаправлению трафика на ранее созданную `backend-group` *backend1*.
4. На заключительном этапе создается сам `ALB` *alb1*, в нем настраивается `listener` *my-listener* на прослушивание 80 порта и перенаправлении трафика на `HTTP-router` *http-router1*.

Проверка создания инфраструктуры в облачной консоли Yandex Cloud:

![VMS](https://github.com/DoctorZub/sys-diplom/blob/main/main/img/vms.png)
![ALB](https://github.com/DoctorZub/sys-diplom/blob/main/main/img/alb.png)
#### Конфигурирование инфраструктуры с помощью Ansible
Повторюсь, что настройка всех ВМ осуществляется удаленно с рабочей станции администратора через Ansible playbooks, а подключение ssh осуществляется через *bastion* host (или, другое название, Jump Host). Для реализации данной концепции на рабочей машине администатора необходимо внести изменения в файл `~/.ssh/config`:
```
Host <Внешний IP-адрес бастиона>
   User user

Host 10.0.*
        ProxyJump <Внешний IP-адрес бастиона>
        User user

Host *.ru-central1.internal
        ProxyJump <Внешний IP-адрес бастиона>
        User user
```

Файл `inventory.yml` для Ansible формируется автоматически в файле [vms.tf](https://github.com/DoctorZub/sys-diplom/blob/main/main/vms.tf) в блоке:
```terraform
resource "local_file" "inventory" {
  content  = <<-XYZ
  [bastion]
  ${yandex_compute_instance.bastion.hostname}.ru-central1.internal

  [webservers]
  ${yandex_compute_instance.web_a.hostname}.ru-central1.internal
  ${yandex_compute_instance.web_b.hostname}.ru-central1.internal
  
  [zabbix]
  ${yandex_compute_instance.zabbix.hostname}.ru-central1.internal

  [elasticsearch]
  ${yandex_compute_instance.elastic.hostname}.ru-central1.internal

  [logstash]
  ${yandex_compute_instance.logstash.hostname}.ru-central1.internal

  [kibana]
  ${yandex_compute_instance.kibana.hostname}.ru-central1.internal
  XYZ
  filename = "./ansible/inventory.yml"
}
```
В данном файле вместо IP-адресов ВМ используются их доменные имена в зоне `ru-central1.internal` вида: *\<hostname>.ru-central1.internal*, которые без проблем "резолвятся" DNS-сервером внутри VPC Yandex Cloud.

Было принято решение - использовать в данной работе отдельные ansible-playbooks для каждого сервера, что позволяет облегчить процесс тестирования при создании или изменении конфигурации отдельного сервиса.
1. [Ansible-playbook для серверов *web-a и web-b*](https://github.com/DoctorZub/sys-diplom/blob/main/main/ansible/webs.yml)  
С помощью него выполняются процессы:
- Установка сервера Nginx;
- Добавление репозиториев Zabbix, установка и настройка Zabbix Agent2;
- Добавление репозиториев Elasticsearch, установка и настройка Filebeat с помощью конфигурационных файлов расположенных в данной [директории](https://github.com/DoctorZub/sys-diplom/tree/main/main/ansible/configs).

![Ansible Webs_1](https://github.com/DoctorZub/sys-diplom/blob/main/main/img/ans_web_1.png)
![Ansible Webs_2](https://github.com/DoctorZub/sys-diplom/blob/main/main/img/ans_web_2.png)
2. [Ansible-playbook для сервера *zabbix*](https://github.com/DoctorZub/sys-diplom/blob/main/main/ansible/zabbix_server.yml)  
С помощью него выполняются процессы:
- Добавление репозиториев Zabbix;
- Установка  Zabbix-Server, Zabbix-frontend, Nginx, PostgreSQL;
- Настройка базы PostgreSQL, Nginx и Zabbix-Server для совместной работы.
   
![Ansible Zabbix](https://github.com/DoctorZub/sys-diplom/blob/main/main/img/ans_zabbix.png)
3. [Ansible-playbook для сервера *elastic*](https://github.com/DoctorZub/sys-diplom/blob/main/main/ansible/elastic.yml)  
С помощью него выполняются процессы:
- Добавление репозиториев Elasticsearch;
- Установка  Elasticsearch;
- Настройка Elasticsearch с помощью конфигурационных файлов расположенных в данной [директории](https://github.com/DoctorZub/sys-diplom/tree/main/main/ansible/configs).
  
![Ansible Elastic](https://github.com/DoctorZub/sys-diplom/blob/main/main/img/ans_elastic.png)
4. [Ansible-playbook для сервера *logstash*](https://github.com/DoctorZub/sys-diplom/blob/main/main/ansible/logstash.yml)  
С помощью него выполняются процессы:
- Добавление репозиториев Elasticsearch;
- Установка  Logstash;
- Настройка Logstash с помощью конфигурационных файлов расположенных в данной [директории](https://github.com/DoctorZub/sys-diplom/tree/main/main/ansible/configs).
  
![Ansible Logstash](https://github.com/DoctorZub/sys-diplom/blob/main/main/img/ans_logstash.png)
5. [Ansible-playbook для сервера *kibana*](https://github.com/DoctorZub/sys-diplom/blob/main/main/ansible/kibana.yml)  
С помощью него выполняются процессы:
- Добавление репозиториев Elasticsearch;
- Установка  Kibana;
- Настройка Kibana с помощью конфигурационных файлов расположенных в данной [директории](https://github.com/DoctorZub/sys-diplom/tree/main/main/ansible/configs).
  
![Ansible Kibana](https://github.com/DoctorZub/sys-diplom/blob/main/main/img/ans_kibana.png)

---
### Сеть
Terraform код, описывающий создание сети и правил сетевого взаимодействия для данной работы, представлен в файле [network.tf](https://github.com/DoctorZub/sys-diplom/blob/main/main/network.tf)  
Кратное описание данного файла:
1. Создается сеть *develop*;
2. Создается 3 подсети:
   - *develop_a* в зоне `ru-central1-a` CIDR `10.0.1.0/24` выход в интернет через `NAT-шлюз` *gateway-1*  
     К данной подсети подключены ВМ: *bastion, web-a, logstash, elastic*. Данные машины (кроме *bastion*) не имеют внешнего IP-адреса. Входящие подключения к ним 
     осуществляются через *bastion* или *ALB*. Исходящий трафик в интернет - через `NAT-шлюз`.
   - *develop_b* в зоне `ru-central1-b` CIDR `10.0.2.0/24` выход в интернет через `NAT-шлюз` *gateway-1*  
     К данной подсети подключена 1 ВМ - *web-b* без внешнего IP-адреса, аналогично серверу *web-a*.
   - *develop_a_pub* в зоне `ru-central1-a` CIDR `192.168.0.0/24`  
     К данной подсети подлючены ВМ, имеющие внешний IP-адрес и доступ к общению через интернет: *zabbix, kibana, ALB*.
3. Создаются группы безопасности (настройки firewall'a):
   - *<ins>LAN</ins>* - это группа безопасности, которая установлена на все ВМ в инфраструктуре, для разрешения взаимодействия внутри сети *develop* (например для разрешения подключения к порту :22 от *bastion*).  
   `Входящий трафик`:
      - `Протокол` - любой;
      - `IPv4_CIDR` - 10.0.0.0/16;
      - `Порт` - 0 - 65535  
    `Исходящий трафик`:
      - без ограничений.  
**<ins>Данее группы безопасности подключаются только к одноименным серверам</ins>**
   - *<ins>bastion</ins>* - разрешается входящий трафик только по ssh (порт :22).  
   `Входящий трафик`:
      - `Протокол` - TCP;
      - `IPv4_CIDR` - 0.0.0.0/0;
      - `Порт` - 22
   - *<ins>webs</ins>* - разрешается входящий трафик от *ALB* по порту :80 и по порту :10050 для подключения к Zabbix-Server.  
   `Входящий трафик`:
      - `Протокол` - TCP;
      - `IPv4_CIDR` - 0.0.0.0/0;
      - `Порт` - 80
      - `Протокол` - ANY;
      - `IPv4_CIDR` - 192.168.0.0/24;
      - `Порт` - 10050
   - *<ins>zabbix-server</ins>* - разрешает входящие подключения на порт :8080 (на котором работает сервер Nginx).  
   `Входящий трафик`:
      - `Протокол` - TCP;
      - `IPv4_CIDR` - 0.0.0.0/0;
      - `Порт` - 8080
   - *<ins>elastic</ins>* - разрешается входящий трафик от *kibana* по порту :9200.  
   `Входящий трафик`:
      - `Протокол` - TCP;
      - `IPv4_CIDR` - 192.168.0.0/24;
      - `Порт` - 9200
   - *<ins>kibana</ins>* - разрешается входящий трафик на стандартный порт работы Kibana :5601.  
   `Входящий трафик`:
      - `Протокол` - TCP;
      - `IPv4_CIDR` - 0.0.0.0/0;
      - `Порт` - 5601
     










---
### Мониторинг(Zabbix)
В качестве системы мониторинга используется `Zabbix-Server версии 7.0` с базой данных `PostgreSQL`. В качестве веб-сервера - `Nginx`, настроенный на порт 8080.  
При настройке сервера в [ansible-playbook](https://github.com/DoctorZub/sys-diplom/blob/main/main/ansible/zabbix_server.yml) необходимо указать пароль, который используется при создании пользователя *zabbix* в базе данных и указывается в файле `/etc/zabbix/zabbix_server.conf`. Данный пароль потребуется при первичном подключении к Zabbix-Server.  

![Подключение к Zabbix](https://github.com/DoctorZub/sys-diplom/blob/main/main/img/zabbix_1.png)  

После успешного подключения к серверу необходимо войти под учетной записью администратора (стандартный логин *Admin*, пароль *zabbix*). После авторизации пароль можно поменять в веб-интерфейсе сервера.  

![Подключение к Zabbix](https://github.com/DoctorZub/sys-diplom/blob/main/main/img/zabbix_2.png) 
![Password change](https://github.com/DoctorZub/sys-diplom/blob/main/main/img/zabbix_3.png)  

Процесс добавления хостов для мониторинга организован через импорт заранее подготовленного [файла](https://github.com/DoctorZub/sys-diplom/blob/main/main/zabbix/zbx_export_hosts.yaml). Данный файл должен находится на рабочей станции администатора, и для добавления хостов необходимо импортировать файл в разделе *Data collection > Hosts > Import*   

![Import hosts](https://github.com/DoctorZub/sys-diplom/blob/main/main/img/zabbix_4.png)    
![Import hosts](https://github.com/DoctorZub/sys-diplom/blob/main/main/img/zabbix_5.png)

К хостам подключен шаблон `Linux by Zabbix agent`, который содержит достаточное кол-во метрик для мониторинга хоста. Как следует из названия шаблона, метрики собираются с помощью *Zabbix Agent2*, установленного на серверах *web-a и web-b*. Было принято решения использовать именно *Zabbix Agent2*, т.к. он является более новой версией Zabbix агента и, при необходимости, может обеспечить более полный и обширный сбор метрик, а также выполнение множества полезных функций (например: использование плагинов, использование последних версий крипто библиотек(OpenSSL) и т.д.).

На сервере создан Dashboard *Netology_ZubkovDA*, содержащий 4 страницы с графиками `CPU`, `RAM`, `Disk`, `Network`.
1. `CPU`

![CPU-1](https://github.com/DoctorZub/sys-diplom/blob/main/main/img/cpu_1.png)    
![CPU-2](https://github.com/DoctorZub/sys-diplom/blob/main/main/img/cpu_2.png)   

На графиках отображена информация по:
- Загрузке процессора в % - *CPU utilization*;
- Нагрузке на процессор - *CPU Load* - это показатель, который отражает общий спрос на ресурсы процессора со стороны активных процессов и процессов, ожидающих выполнения. Он показывает, сколько задач ждёт в очереди компьютера для обработки процессором;
- Информация о том, сколько времени процессор тратить на выполнение различных процедур - ожидание ввода/вывода, системные прерывания, время бездействия и т.д.

2. `RAM`

![RAM](https://github.com/DoctorZub/sys-diplom/blob/main/main/img/ram.png)

На графиках отображена информация о доступной и использованной оперативной памяти.

3. `Disk`

![Disk-1](https://github.com/DoctorZub/sys-diplom/blob/main/main/img/disk_1.png)    
![Disk-2](https://github.com/DoctorZub/sys-diplom/blob/main/main/img/disk_2.png) 

На графиках отображена информация по:
- Свободному и использованному месту в корневом каталоге файловой системы - *Space utilization chart*;
- Процент времени, в течение которого выбранный диск был занят операциями чтения или записи - *Disk utilization*  и  количество запросов на чтение или запись, ожидающих своей очереди на выполнение диском - *Disk queue size*;
- Среднее время ожидания запросов на чтение и запись - *Disk average waiting time*;
- Скорость чтения и записи - *Disk read/write rates*.

4. `Network`

![Network](https://github.com/DoctorZub/sys-diplom/blob/main/main/img/network.png)

На графике представлены следующие метрики:
- Скорость загрузки и выгрузки - *Bits received* *Bits sent*;
- Пакеты с ошибками - *Inbound/outbound packages with errors*
- Отброшенные пакеты - *Inbound/outbound packages discarded*;
- Статус интерфейса - *Operational status* - где 6 - это **"интерфейс поднят и готов к использованию"**.

---
### Сбор логов(ELK)
Процесс сбора и настройки логов огранизован через ELK-стек (Elasticsearch, Logstash, Kibana), по 1-й ВМ на каждый сервис. Сбор логов с веб-серверов *web-a и web-b* осуществляется с помощью `Filebeat`, установленного на серверах.  

Конфигурация *filebeat* представлена в [файле](https://github.com/DoctorZub/sys-diplom/blob/main/main/ansible/configs/filebeat/filebeat.yml):
- Логи собираются с двух файлов сервера Nginx - `/var/log/nginx/access.log` и `/var/log/nginx/error.log`;
- Для того, чтобы отличать, из какого файла пришло сообщение, используются теги (tags);
- Собранные логи отправляются на сервер с Logstash по адресу `logstash.ru-central1.internal:5044`.

Конфигурация [*logstash*](https://github.com/DoctorZub/sys-diplom/blob/main/main/ansible/configs/logstash/pipelines.yml):
- Указывается, что будет выполняться один единственный pipeline - [beat_nginx.conf](https://github.com/DoctorZub/sys-diplom/blob/main/main/ansible/configs/logstash/beat_nginx.conf);
- В pipeline прописано, что прием сообщений осуществляется с `beats` на порт :5044;
- Поступившие сообщения фильтруются в соответсвии с *tags* с помощью `grok`. Для логов с `/var/log/nginx/access.log` и `/var/log/nginx/error.log` прописаны разные выражения фильтрации.
- Обработанные, отфильтрованные сообщения отправляются на сервер с Elasticsearch по адресу `elastic.ru-central1.internal:9200`

Конфигурация [*elasticsearch*](https://github.com/DoctorZub/sys-diplom/blob/main/main/ansible/configs/logstash/pipelines.yml):
- Указывается имя кластера - *Zubkov*;
- Заполняется поле `network.host: elastic.ru-central1.internal`, определяющее адрес, по которому можно обратиться к Elasticsearch из вне;
- Отключаются функции безопасности `xpack.security.enabled: false`, т.к. в данной работе они не настраиваются.

Конфигурация [*kibana*](https://github.com/DoctorZub/sys-diplom/blob/main/main/ansible/configs/logstash/pipelines.yml):
- Разрешаются внешние подключения с любых хостов на порт :5601 - `server.port: 5601` `server.host: "0.0.0.0"`;
- Указывается URL адрес хоста с Elasticsearch - `elasticsearch.hosts: ["http://elastic.ru-central1.internal:9200"]`.

Для отображения данных с Elasticsearch в Kibana было совершено несколько подключений к серверам *web-a и web-b* через публичный адрекс ALB.  
После этого в веб-интерфейсе Kibana в разделе *Management > Stack Management > Kibana > Data Views* необходимо создать *Data View* из данных Elasticsearch.

![Kibana-1](https://github.com/DoctorZub/sys-diplom/blob/main/main/img/kibana_1.png)    
![Kibana-2](https://github.com/DoctorZub/sys-diplom/blob/main/main/img/kibana_2.png)

После создания приходящие в Elasticsearch логи можно посмотреть в разделе *Analytics > Discover*.

![Kibana-3](https://github.com/DoctorZub/sys-diplom/blob/main/main/img/kibana_3.png) 

Был создан *Data View* под названием *nginx*, и настроено удобное представление отдельных полей логов:
- `@timestamp` - время создания и считывания лога;
- `ip` - IP-адрес, откуда происходило подключение к серверу *Nginx*, в данной работе - это IP-адреса балансировщика нагрузки;
- `agent.name` `agent.type` - имя и тип агента, можно отследить с какого именно сервера получены логи от filebeat;
- `http.method` - метод HTTP;
- `log.file.path` - лог-файл, с которого считан лог;
- `referrer` - HTTP-Referrer;
- `url` - на какой путь выполнялось подключение к серверу;
- `remote_agent` - с какого агента/приложения выполнялось подключение.





---
### Резервное копирование
В качестве технологии резервного копирования в данной работе выбрана технология создания снимков (snapshots) дисков. Снимки дисков создаются для всех ВМ по определенному расписанию.

Для реализации данной концепции используется встроенный в Yandex Cloud сервис - *Snapshots*. Terraform код - [snapshots.tf](https://github.com/DoctorZub/sys-diplom/blob/main/main/shapshot.tf).  
С помощью данного файла:
- Cоздается расписание создания снимков через cron-выражение - `"0 22 ? * *"` - означающее, что снимки будут создаваться каждый день в 3 часа ночи (03:00) для часового пояса UTC+5 Yekaterinburg (т.к. настройка расписания сервиса *Snapshots* выполняется по часовому поясу UTC+0);
- Указывается кол-во хранящихся снимков - ` snapshot_count = 7`;
- Осуществляется подключение дисков всех ВМ в инфраструктуре к данному расписанию.

Проверка создания расписания в облачной консоли Yandex Cloud

![Snapshot]()

---
### Заключение
---

