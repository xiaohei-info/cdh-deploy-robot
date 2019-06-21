#!/bin/expect

if {$argc != 5} {
    puts "Usage:cmd <exec> <host> <user> <passwd> <command>"
    exit 1
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
       "enter for none" { send "\n"; exp_continue}
       "Y/n" { send "Y\n" ; exp_continue}
       "password:" { send "$passwd\n"; exp_continue}
       "new password:" { send "$passwd\n"; exp_continue}
       "Y/n" { send "Y\n" ; exp_continue}
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
    if {[connect $passwd]} {
        exit 1
    }
} else {
    puts "exec type error"
}

expect eof


