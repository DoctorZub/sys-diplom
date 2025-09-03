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


## Конфигурирование инфраструктуры с помощью Ansible
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
В данном файле вместо IP-адресов ВМ используются их доменные имена в зоне `ru-central1.internal` вида: *<hostname>.ru-central1.internal*, которые без проблем "резолвятся" DNS-сервером внутри VPC Yandex Cloud.

---
### Сеть
---
### Мониторинг(Zabbix)
---
### Сбор логов(ELK)
---
### Резервное копирование
---
### Заключение
---

