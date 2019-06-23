#!/bin/expect

if {$argc != 5} {
    puts "Usage:cmd <exec> <host> <user> <passwd> <command>"
    exit 1
}

proc init_mysql_passwd {init_passwd new_passwd} {
  expect {
    "*Enter password for user root*" { send "$init_passwd\n"; exp_continue}
    "*New password*" { send "$new_passwd\n" ; exp_continue}
    "*Re-enter new password*" { send "$new_passwd\n"; exp_continue}
    "*Do you wish to continue with the password provided*" { send "y\n"; exp_continue}
    "*Change the password for root*" { send "y\n"; exp_continue}
    "*Remove anonymous users*" { send "y\n"; exp_continue}
    "*Disallow root login remotely*" { send "\n"; exp_continue}
    "*Remove test database and access to it*" { send "y\n"; exp_continue}
    "*Reload privilege tables now*" { send "y\n"; exp_continue}
    "*Enter SCM password*" { send "$new_passwd\n"; exp_continue}
    "*#" { return 0}
  }
  return 1
}

proc connect {passwd} {
   expect {
       "(yes/no)?" {
           send "yes\n"
           expect "*password:" {
                send "$passwd\n"
                expect {
                    "*#" {
                        return 0
                    }
                }
           }
       }
       "*'s password:" {
           send "$passwd\n"
           expect {
                "Overwrite (y/n)" {
                    send "y\n"
                    exp_continue
                }
                "*file in which to save the key*" {
                    send "\n"
                    exp_continue
                }
                "*Enter passphrase*" {
                    send "\n"
                    exp_continue
                }
                "*Enter same passphrase again*" {
                    send "\n"
                    exp_continue
                }
               "*#" {
                   return 0
               }
           }
       }
   }
   return 1
}

set timeout 30
set exec [lindex $argv 0] 
set host [lindex $argv 1] 
set user [lindex $argv 2] 
set passwd [lindex $argv 3]
set cmd  [lindex $argv 4]

if {$exec == "ssh"} {
    spawn ssh $user@$host $cmd
    if {[connect $passwd]} {
        exit 1
    }
} elseif {$exec == "scp"} {
    spawn scp $cmd $user@$host:$cmd
    if {[connect $passwd]} {
        exit 1
    }
} elseif {$exec == "get"} {
    spawn scp $user@$host:$cmd $cmd
    if {[connect $passwd]} {
        exit 1
    }
} elseif {$exec == "mysql_init"} {
    spawn /usr/bin/mysql_secure_installation
    if {[init_mysql_passwd $passwd $cmd]} {
        exit 1
    }
} elseif {$exec == "cm_init" } {
    spawn /opt/cloudera/cm/schema/scm_prepare_database.sh -h $host mysql scm scm
    if {[init_mysql_passwd $passwd $cmd]} {
        exit 1
    }
} else {
    puts "exec type error"
}

expect eof


