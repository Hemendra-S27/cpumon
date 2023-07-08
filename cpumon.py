import tkinter as tk
from tkinter import ttk
import psutil
import time
import threading

class Application(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("CPU Monitor")
        
        self.cpus = psutil.cpu_count()
        self.cpu_vars = [tk.DoubleVar(value=0) for _ in range(self.cpus)]
        self.progress_bars = []

        for i in range(self.cpus):
            ttk.Label(self, text=f"CPU {i+1}").grid(column=0, row=i)
            pb = ttk.Progressbar(self, maximum=100, length=300, variable=self.cpu_vars[i])
            pb.grid(column=1, row=i, padx=10, pady=5)
            self.progress_bars.append(pb)

        self.update_cpu_usage()

    def update_cpu_usage(self):
        cpu_percentages = psutil.cpu_percent(percpu=True)
        for i in range(self.cpus):
            self.cpu_vars[i].set(cpu_percentages[i])
        self.after(1000, self.update_cpu_usage)


if __name__ == "__main__":
    app = Application()
    app.mainloop()
