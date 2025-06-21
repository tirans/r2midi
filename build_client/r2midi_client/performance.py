"""
Performance monitoring for R2MIDI application
"""

import asyncio
import logging
import statistics
import time
from dataclasses import dataclass, field
from datetime import datetime
from typing import Callable, Dict, List, Optional

import psutil

logger = logging.getLogger(__name__)


@dataclass
class PerformanceMetric:
    """Performance metric data"""

    name: str
    value: float
    unit: str
    timestamp: datetime = field(default_factory=datetime.now)


@dataclass
class PerformanceSnapshot:
    """Snapshot of system performance"""

    cpu_percent: float
    memory_percent: float
    memory_mb: float
    thread_count: int
    timestamp: datetime = field(default_factory=datetime.now)


class PerformanceMonitor:
    """Monitor application performance metrics"""

    def __init__(self):
        self.metrics: Dict[str, List[PerformanceMetric]] = {}
        self.snapshots: List[PerformanceSnapshot] = []
        self.operation_timers: Dict[str, float] = {}
        self.process = psutil.Process()
        self._monitoring = False
        self._monitor_task = None

    def start_monitoring(self, interval: float = 1.0):
        """Start continuous performance monitoring"""
        if self._monitoring:
            return

        self._monitoring = True
        logger.info(f"Performance monitoring started (interval: {interval}s)")

    async def start_monitoring_async(self, interval: float = 1.0):
        """Start continuous performance monitoring asynchronously"""
        if self._monitoring:
            return

        self._monitoring = True
        self._monitor_task = asyncio.create_task(self._monitor_loop(interval))
        logger.info(
            f"Performance monitoring started asynchronously (interval: {interval}s)"
        )

    def stop_monitoring(self):
        """Stop performance monitoring"""
        self._monitoring = False
        if self._monitor_task:
            self._monitor_task.cancel()
        logger.info("Performance monitoring stopped")

    async def _monitor_loop(self, interval: float):
        """Monitoring loop"""
        while self._monitoring:
            try:
                self.take_snapshot()
                await asyncio.sleep(interval)
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error in monitoring loop: {e}")

    def take_snapshot(self) -> PerformanceSnapshot:
        """Take a performance snapshot"""
        try:
            cpu_percent = self.process.cpu_percent()
            memory_info = self.process.memory_info()
            memory_percent = self.process.memory_percent()
            memory_mb = memory_info.rss / 1024 / 1024
            thread_count = self.process.num_threads()

            snapshot = PerformanceSnapshot(
                cpu_percent=cpu_percent,
                memory_percent=memory_percent,
                memory_mb=memory_mb,
                thread_count=thread_count,
            )

            self.snapshots.append(snapshot)

            # Keep only last 1000 snapshots
            if len(self.snapshots) > 1000:
                self.snapshots = self.snapshots[-1000:]

            return snapshot

        except Exception as e:
            logger.error(f"Error taking snapshot: {e}")
            return PerformanceSnapshot(0, 0, 0, 0)

    def start_operation(self, operation_name: str):
        """Start timing an operation"""
        self.operation_timers[operation_name] = time.time()

    def end_operation(self, operation_name: str) -> Optional[float]:
        """End timing an operation and record the metric"""
        if operation_name not in self.operation_timers:
            logger.warning(f"No start time for operation: {operation_name}")
            return None

        start_time = self.operation_timers.pop(operation_name)
        duration = time.time() - start_time

        self.record_metric(f"{operation_name}_duration", duration, "seconds")
        return duration

    def record_metric(self, name: str, value: float, unit: str = ""):
        """Record a performance metric"""
        metric = PerformanceMetric(name=name, value=value, unit=unit)

        if name not in self.metrics:
            self.metrics[name] = []

        self.metrics[name].append(metric)

        # Keep only last 100 metrics per name
        if len(self.metrics[name]) > 100:
            self.metrics[name] = self.metrics[name][-100:]

        logger.debug(f"Recorded metric: {name}={value}{unit}")

    def get_average_metric(self, name: str) -> Optional[float]:
        """Get average value of a metric"""
        if name not in self.metrics or not self.metrics[name]:
            return None

        values = [m.value for m in self.metrics[name]]
        return statistics.mean(values)

    def get_metric_stats(self, name: str) -> Optional[Dict[str, float]]:
        """Get statistics for a metric"""
        if name not in self.metrics or not self.metrics[name]:
            return None

        values = [m.value for m in self.metrics[name]]

        return {
            "min": min(values),
            "max": max(values),
            "mean": statistics.mean(values),
            "median": statistics.median(values),
            "stdev": statistics.stdev(values) if len(values) > 1 else 0,
        }

    def get_performance_summary(self) -> Dict[str, any]:
        """Get a summary of performance metrics"""
        if not self.snapshots:
            return {}

        recent_snapshots = self.snapshots[-60:]  # Last minute

        return {
            "current": {
                "cpu_percent": self.snapshots[-1].cpu_percent if self.snapshots else 0,
                "memory_mb": self.snapshots[-1].memory_mb if self.snapshots else 0,
                "thread_count": (
                    self.snapshots[-1].thread_count if self.snapshots else 0
                ),
            },
            "average": {
                "cpu_percent": statistics.mean(
                    [s.cpu_percent for s in recent_snapshots]
                ),
                "memory_mb": statistics.mean([s.memory_mb for s in recent_snapshots]),
            },
            "peak": {
                "cpu_percent": max([s.cpu_percent for s in recent_snapshots]),
                "memory_mb": max([s.memory_mb for s in recent_snapshots]),
            },
            "operation_stats": {
                name: self.get_metric_stats(name)
                for name in self.metrics
                if name.endswith("_duration")
            },
        }

    def log_summary(self):
        """Log a performance summary"""
        summary = self.get_performance_summary()
        if not summary:
            return

        logger.info("Performance Summary:")
        logger.info(f"  Current CPU: {summary['current']['cpu_percent']:.1f}%")
        logger.info(f"  Current Memory: {summary['current']['memory_mb']:.1f} MB")
        logger.info(f"  Average CPU: {summary['average']['cpu_percent']:.1f}%")
        logger.info(f"  Peak Memory: {summary['peak']['memory_mb']:.1f} MB")

        if summary.get("operation_stats"):
            logger.info("  Operation timings:")
            for op, stats in summary["operation_stats"].items():
                if stats:
                    logger.info(
                        f"    {op}: avg={stats['mean']:.3f}s, "
                        f"min={stats['min']:.3f}s, max={stats['max']:.3f}s"
                    )


class PerformanceContext:
    """Context manager for timing operations"""

    def __init__(self, monitor: PerformanceMonitor, operation_name: str):
        self.monitor = monitor
        self.operation_name = operation_name

    def __enter__(self):
        self.monitor.start_operation(self.operation_name)
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        duration = self.monitor.end_operation(self.operation_name)
        if duration and duration > 1.0:  # Log slow operations
            logger.warning(
                f"Slow operation: {self.operation_name} took {duration:.2f}s"
            )


# Global performance monitor instance
_monitor = None


def get_monitor() -> PerformanceMonitor:
    """Get the global performance monitor instance"""
    global _monitor
    if _monitor is None:
        _monitor = PerformanceMonitor()
    return _monitor


def monitor_operation(operation_name: str):
    """Decorator to monitor operation performance"""

    def decorator(func):
        def wrapper(*args, **kwargs):
            with PerformanceContext(get_monitor(), operation_name):
                return func(*args, **kwargs)

        return wrapper

    return decorator


def monitor_async_operation(operation_name: str):
    """Decorator to monitor async operation performance"""

    def decorator(func):
        async def wrapper(*args, **kwargs):
            monitor = get_monitor()
            monitor.start_operation(operation_name)
            try:
                result = await func(*args, **kwargs)
                return result
            finally:
                monitor.end_operation(operation_name)

        return wrapper

    return decorator
