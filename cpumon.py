import os
import psutil
import time
from termcolor import colored

def print_cpu_utilization():
    cpu_utilization = psutil.cpu_times_percent(interval=1)

    sys_utilization = cpu_utilization.system
    user_utilization = cpu_utilization.user
    idle_utilization = cpu_utilization.idle

    print(colored("System Utilization", "red"))
    print(colored("|" * int(sys_utilization), "red"))

    print(colored("User Utilization", "blue"))
    print(colored("|" * int(user_utilization), "blue"))

    print(colored("Idle Utilization", "green"))
    print(colored("|" * int(idle_utilization), "green"))

    print("\n")

while True:
    os.system('clear')
    print_cpu_utilization()
    time.sleep(1)
