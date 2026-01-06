#!/usr/bin/env python3
"""
Performance Analytics and Reporting System
Comprehensive analytics for blockchain node performance monitoring and reporting

Features:
- Historical performance data analysis
- Performance trend analysis
- Resource utilization metrics
- Sync performance analytics
- Network connectivity analysis
- Automated report generation
- Performance recommendations
"""

import json
import sqlite3
import statistics
from datetime import datetime, timedelta
from typing import Dict, Any, List, Optional, Tuple
from dataclasses import dataclass, asdict
import logging
import yaml
import matplotlib.pyplot as plt
import pandas as pd
from pathlib import Path

@dataclass
class PerformanceMetrics:
    """Performance metrics data structure"""
    timestamp: datetime
    node_name: str
    sync_progress: float
    block_number: int
    peers: int
    memory_mb: float
    cpu_percent: float
    health_score: float
    response_time_ms: float
    sync_speed_bph: float = 0.0  # blocks per hour
    disk_io_mb: float = 0.0
    network_rx_mb: float = 0.0
    network_tx_mb: float = 0.0

@dataclass
class PerformanceTrend:
    """Performance trend analysis result"""
    metric: str
    trend: str  # improving, degrading, stable
    change_rate: float
    confidence: float
    data_points: int

class PerformanceAnalytics:
    """Advanced performance analytics system"""

    def __init__(self, db_path: str = "/var/lib/blockchain/sync_verification.db"):
        self.db_path = db_path
        self.logger = logging.getLogger(__name__)
        self.plots_dir = Path("/var/log/blockchain/plots")
        self.plots_dir.mkdir(parents=True, exist_ok=True)

    def get_historical_data(self, node_name: str = None, hours: int = 24) -> List[PerformanceMetrics]:
        """Get historical performance data"""
        try:
            with sqlite3.connect(self.db_path) as conn:
                where_clause = ""
                params = []

                if node_name:
                    where_clause = "WHERE node_name = ?"
                    params.append(node_name)

                where_clause += f" AND timestamp > datetime('now', '-{hours} hours')" if params else f"WHERE timestamp > datetime('now', '-{hours} hours')"

                query = f'''
                    SELECT timestamp, node_name, sync_progress, current_block, peers,
                           memory_mb, cpu_percent, health_score
                    FROM sync_status
                    {where_clause}
                    ORDER BY timestamp ASC
                '''

                cursor = conn.execute(query, params)
                rows = cursor.fetchall()

                metrics = []
                for row in rows:
                    metrics.append(PerformanceMetrics(
                        timestamp=datetime.fromisoformat(row[0]),
                        node_name=row[1],
                        sync_progress=row[2] or 0.0,
                        block_number=row[3] or 0,
                        peers=row[4] or 0,
                        memory_mb=row[5] or 0.0,
                        cpu_percent=row[6] or 0.0,
                        health_score=row[7] or 0.0,
                        response_time_ms=0.0  # Would need additional tracking
                    ))

                return metrics
        except Exception as e:
            self.logger.error(f"Failed to get historical data: {e}")
            return []

    def analyze_performance_trends(self, node_name: str, hours: int = 24) -> List[PerformanceTrend]:
        """Analyze performance trends for a specific node"""
        metrics = self.get_historical_data(node_name, hours)
        if len(metrics) < 2:
            return []

        trends = []

        # Analyze sync progress trend
        sync_trend = self._calculate_trend([m.sync_progress for m in metrics], 'sync_progress')
        if sync_trend:
            trends.append(sync_trend)

        # Analyze health score trend
        health_trend = self._calculate_trend([m.health_score for m in metrics], 'health_score')
        if health_trend:
            trends.append(health_trend)

        # Analyze memory usage trend
        memory_trend = self._calculate_trend([m.memory_mb for m in metrics], 'memory_mb')
        if memory_trend:
            trends.append(memory_trend)

        # Analyze CPU usage trend
        cpu_trend = self._calculate_trend([m.cpu_percent for m in metrics], 'cpu_percent')
        if cpu_trend:
            trends.append(cpu_trend)

        # Analyze peer count trend
        peer_trend = self._calculate_trend([m.peers for m in metrics], 'peers')
        if peer_trend:
            trends.append(peer_trend)

        return trends

    def _calculate_trend(self, values: List[float], metric_name: str) -> Optional[PerformanceTrend]:
        """Calculate trend for a series of values"""
        if len(values) < 3:
            return None

        try:
            # Calculate linear regression
            x = list(range(len(values)))
            n = len(values)

            sum_x = sum(x)
            sum_y = sum(values)
            sum_xy = sum(x[i] * values[i] for i in range(n))
            sum_x2 = sum(x[i] ** 2 for i in range(n))

            # Calculate slope (change per time unit)
            slope = (n * sum_xy - sum_x * sum_y) / (n * sum_x2 - sum_x ** 2)

            # Determine trend direction
            if abs(slope) < 0.01:
                trend_direction = "stable"
            elif slope > 0:
                trend_direction = "improving"
            else:
                trend_direction = "degrading"

            # Calculate confidence based on variance
            if len(values) > 1:
                variance = statistics.variance(values)
                mean = statistics.mean(values)
                coefficient_of_variation = (variance ** 0.5) / mean if mean != 0 else float('inf')
                confidence = max(0, min(100, 100 - coefficient_of_variation * 20))
            else:
                confidence = 0

            return PerformanceTrend(
                metric=metric_name,
                trend=trend_direction,
                change_rate=slope,
                confidence=confidence,
                data_points=len(values)
            )
        except Exception as e:
            self.logger.error(f"Failed to calculate trend for {metric_name}: {e}")
            return None

    def generate_performance_report(self, node_name: str = None, hours: int = 24,
                                   output_format: str = "json") -> Dict[str, Any]:
        """Generate comprehensive performance report"""
        self.logger.info(f"Generating performance report for {node_name or 'all nodes'}")

        report = {
            'report_metadata': {
                'timestamp': datetime.now().isoformat(),
                'analysis_period_hours': hours,
                'node_filter': node_name or 'all',
                'report_version': '1.0'
            },
            'summary': {},
            'nodes': {},
            'trends': {},
            'recommendations': [],
            'alerts': []
        }

        # Get historical data
        metrics = self.get_historical_data(node_name, hours)
        if not metrics:
            report['summary']['status'] = 'no_data'
            report['summary']['message'] = 'No historical data available'
            return report

        # Group metrics by node
        nodes_data = {}
        for metric in metrics:
            if metric.node_name not in nodes_data:
                nodes_data[metric.node_name] = []
            nodes_data[metric.node_name].append(metric)

        # Analyze each node
        for current_node, node_metrics in nodes_data.items():
            node_report = self._analyze_node_performance(current_node, node_metrics)
            report['nodes'][current_node] = node_report

            # Get trends for this node
            trends = self.analyze_performance_trends(current_node, hours)
            report['trends'][current_node] = [asdict(trend) for trend in trends]

        # Generate overall summary
        report['summary'] = self._generate_overall_summary(nodes_data, report['nodes'])

        # Generate recommendations
        report['recommendations'] = self._generate_performance_recommendations(report['nodes'], report['trends'])

        # Generate alerts based on performance issues
        report['alerts'] = self._generate_performance_alerts(report['nodes'])

        return report

    def _analyze_node_performance(self, node_name: str, metrics: List[PerformanceMetrics]) -> Dict[str, Any]:
        """Analyze performance for a specific node"""
        if not metrics:
            return {}

        latest = metrics[-1]
        earliest = metrics[0]

        # Calculate averages
        avg_sync_progress = statistics.mean([m.sync_progress for m in metrics])
        avg_health_score = statistics.mean([m.health_score for m in metrics])
        avg_peers = statistics.mean([m.peers for m in metrics])
        avg_memory = statistics.mean([m.memory_mb for m in metrics])
        avg_cpu = statistics.mean([m.cpu_percent for m in metrics])

        # Calculate performance changes
        sync_change = latest.sync_progress - earliest.sync_progress
        block_change = latest.block_number - earliest.block_number
        health_change = latest.health_score - earliest.health_score

        # Calculate performance stability (coefficient of variation)
        sync_stability = self._calculate_stability([m.sync_progress for m in metrics])
        health_stability = self._calculate_stability([m.health_score for m in metrics])

        # Calculate sync speed
        time_hours = (latest.timestamp - earliest.timestamp).total_seconds() / 3600
        sync_speed_bph = block_change / time_hours if time_hours > 0 else 0

        return {
            'node_name': node_name,
            'analysis_period': {
                'start': earliest.timestamp.isoformat(),
                'end': latest.timestamp.isoformat(),
                'duration_hours': time_hours
            },
            'current_status': {
                'sync_progress': latest.sync_progress,
                'block_number': latest.block_number,
                'health_score': latest.health_score,
                'peers': latest.peers,
                'memory_mb': latest.memory_mb,
                'cpu_percent': latest.cpu_percent
            },
            'performance_averages': {
                'sync_progress': avg_sync_progress,
                'health_score': avg_health_score,
                'peers': avg_peers,
                'memory_mb': avg_memory,
                'cpu_percent': avg_cpu
            },
            'performance_changes': {
                'sync_progress_change': sync_change,
                'blocks_synced': block_change,
                'health_score_change': health_change,
                'sync_speed_bph': sync_speed_bph
            },
            'stability_metrics': {
                'sync_stability': sync_stability,
                'health_stability': health_stability
            },
            'performance_grade': self._calculate_performance_grade(avg_health_score, sync_stability)
        }

    def _calculate_stability(self, values: List[float]) -> float:
        """Calculate stability metric (lower coefficient of variation = more stable)"""
        if len(values) < 2:
            return 100.0

        try:
            mean = statistics.mean(values)
            if mean == 0:
                return 0.0

            std_dev = statistics.stdev(values)
            coefficient_of_variation = std_dev / mean
            stability = max(0, 100 - coefficient_of_variation * 50)  # Scale to 0-100
            return min(100, stability)
        except:
            return 0.0

    def _calculate_performance_grade(self, avg_health: float, stability: float) -> str:
        """Calculate overall performance grade"""
        score = (avg_health * 0.7) + (stability * 0.3)

        if score >= 90:
            return 'A+'
        elif score >= 85:
            return 'A'
        elif score >= 80:
            return 'B+'
        elif score >= 75:
            return 'B'
        elif score >= 70:
            return 'C+'
        elif score >= 65:
            return 'C'
        elif score >= 60:
            return 'D'
        else:
            return 'F'

    def _generate_overall_summary(self, nodes_data: Dict[str, List[PerformanceMetrics]],
                                node_reports: Dict[str, Dict[str, Any]]) -> Dict[str, Any]:
        """Generate overall summary statistics"""
        total_nodes = len(nodes_data)
        if total_nodes == 0:
            return {'status': 'no_nodes', 'message': 'No nodes found'}

        # Calculate averages across all nodes
        all_health_scores = []
        all_sync_progress = []
        all_grades = []

        for node_name, report in node_reports.items():
            if 'current_status' in report:
                all_health_scores.append(report['current_status']['health_score'])
                all_sync_progress.append(report['current_status']['sync_progress'])
                all_grades.append(report.get('performance_grade', 'F'))

        avg_health = statistics.mean(all_health_scores) if all_health_scores else 0
        avg_sync = statistics.mean(all_sync_progress) if all_sync_progress else 0

        # Grade distribution
        grade_distribution = {}
        for grade in all_grades:
            grade_distribution[grade] = grade_distribution.get(grade, 0) + 1

        return {
            'status': 'success',
            'total_nodes': total_nodes,
            'average_health_score': avg_health,
            'average_sync_progress': avg_sync,
            'grade_distribution': grade_distribution,
            'nodes_with_issues': sum(1 for h in all_health_scores if h < 70),
            'nodes_performing_well': sum(1 for h in all_health_scores if h >= 80)
        }

    def _generate_performance_recommendations(self, node_reports: Dict[str, Dict[str, Any]],
                                            trends: Dict[str, List[PerformanceTrend]]) -> List[str]:
        """Generate performance recommendations based on analysis"""
        recommendations = []

        # Analyze each node for issues
        for node_name, report in node_reports.items():
            current = report.get('current_status', {})
            performance_changes = report.get('performance_changes', {})
            stability = report.get('stability_metrics', {})

            # Health score recommendations
            if current.get('health_score', 0) < 70:
                recommendations.append(f"{node_name}: Low health score detected - investigate system issues")

            # Memory usage recommendations
            if current.get('memory_mb', 0) > 16000:  # 16GB
                recommendations.append(f"{node_name}: High memory usage - consider optimization or additional RAM")

            # CPU usage recommendations
            if current.get('cpu_percent', 0) > 85:
                recommendations.append(f"{node_name}: High CPU usage - check for resource bottlenecks")

            # Sync speed recommendations
            sync_speed = performance_changes.get('sync_speed_bph', 0)
            if sync_speed < 100 and current.get('sync_progress', 0) < 95:
                recommendations.append(f"{node_name}: Slow sync speed ({sync_speed:.0f} blocks/hour) - check network connectivity")

            # Stability recommendations
            if stability.get('sync_stability', 100) < 70:
                recommendations.append(f"{node_name}: Unstable sync progress - monitor for consistency")

            # Trend-based recommendations
            node_trends = trends.get(node_name, [])
            for trend in node_trends:
                if trend.trend == 'degrading' and trend.confidence > 70:
                    recommendations.append(f"{node_name}: {trend.metric} is degrading - investigate cause")

        # Remove duplicates and limit
        unique_recommendations = list(set(recommendations))
        return unique_recommendations[:10]  # Limit to top 10 recommendations

    def _generate_performance_alerts(self, node_reports: Dict[str, Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Generate performance alerts based on current status"""
        alerts = []

        for node_name, report in node_reports.items():
            current = report.get('current_status', {})

            # Critical alerts
            if current.get('health_score', 0) < 50:
                alerts.append({
                    'severity': 'critical',
                    'node': node_name,
                    'message': f'Critical health score: {current.get("health_score", 0):.1f}%',
                    'timestamp': datetime.now().isoformat()
                })

            if current.get('memory_mb', 0) > 24000:  # 24GB
                alerts.append({
                    'severity': 'critical',
                    'node': node_name,
                    'message': f'Critical memory usage: {current.get("memory_mb", 0)/1024:.1f}GB',
                    'timestamp': datetime.now().isoformat()
                })

            # Warning alerts
            if current.get('cpu_percent', 0) > 90:
                alerts.append({
                    'severity': 'warning',
                    'node': node_name,
                    'message': f'High CPU usage: {current.get("cpu_percent", 0):.1f}%',
                    'timestamp': datetime.now().isoformat()
                })

            if current.get('peers', 0) < 5:
                alerts.append({
                    'severity': 'warning',
                    'node': node_name,
                    'message': f'Low peer count: {current.get("peers", 0)}',
                    'timestamp': datetime.now().isoformat()
                })

        return alerts

    def create_performance_plots(self, node_name: str, hours: int = 24) -> List[str]:
        """Create performance visualization plots"""
        metrics = self.get_historical_data(node_name, hours)
        if len(metrics) < 2:
            return []

        plots = []
        timestamps = [m.timestamp for m in metrics]

        # Plot 1: Sync Progress and Health Score
        fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 8))
        fig.suptitle(f'{node_name} - Sync Progress & Health Score', fontsize=16)

        # Sync progress
        sync_progress = [m.sync_progress for m in metrics]
        ax1.plot(timestamps, sync_progress, 'b-', label='Sync Progress')
        ax1.set_ylabel('Sync Progress (%)')
        ax1.set_ylim(0, 105)
        ax1.grid(True, alpha=0.3)
        ax1.legend()

        # Health score
        health_scores = [m.health_score for m in metrics]
        ax2.plot(timestamps, health_scores, 'r-', label='Health Score')
        ax2.set_ylabel('Health Score (%)')
        ax2.set_xlabel('Time')
        ax2.set_ylim(0, 105)
        ax2.grid(True, alpha=0.3)
        ax2.legend()

        # Rotate x-axis labels
        for ax in [ax1, ax2]:
            for label in ax.get_xticklabels():
                label.set_rotation(45)
                label.set_ha('right')

        plt.tight_layout()
        plot_file = self.plots_dir / f'{node_name}_sync_health_{datetime.now().strftime("%Y%m%d_%H%M%S")}.png'
        plt.savefig(plot_file, dpi=300, bbox_inches='tight')
        plt.close()
        plots.append(str(plot_file))

        # Plot 2: Resource Usage
        fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 8))
        fig.suptitle(f'{node_name} - Resource Usage', fontsize=16)

        # Memory usage
        memory_usage = [m.memory_mb / 1024 for m in metrics]  # Convert to GB
        ax1.plot(timestamps, memory_usage, 'g-', label='Memory Usage')
        ax1.set_ylabel('Memory (GB)')
        ax1.grid(True, alpha=0.3)
        ax1.legend()

        # CPU usage
        cpu_usage = [m.cpu_percent for m in metrics]
        ax2.plot(timestamps, cpu_usage, 'orange', label='CPU Usage')
        ax2.set_ylabel('CPU Usage (%)')
        ax2.set_xlabel('Time')
        ax2.grid(True, alpha=0.3)
        ax2.legend()

        # Rotate x-axis labels
        for ax in [ax1, ax2]:
            for label in ax.get_xticklabels():
                label.set_rotation(45)
                label.set_ha('right')

        plt.tight_layout()
        plot_file = self.plots_dir / f'{node_name}_resources_{datetime.now().strftime("%Y%m%d_%H%M%S")}.png'
        plt.savefig(plot_file, dpi=300, bbox_inches='tight')
        plt.close()
        plots.append(str(plot_file))

        return plots

    def export_to_csv(self, node_name: str = None, hours: int = 24, output_file: str = None) -> str:
        """Export performance data to CSV"""
        metrics = self.get_historical_data(node_name, hours)
        if not metrics:
            return ""

        # Convert to DataFrame
        data = []
        for metric in metrics:
            data.append({
                'timestamp': metric.timestamp,
                'node_name': metric.node_name,
                'sync_progress': metric.sync_progress,
                'block_number': metric.block_number,
                'peers': metric.peers,
                'memory_mb': metric.memory_mb,
                'cpu_percent': metric.cpu_percent,
                'health_score': metric.health_score,
                'response_time_ms': metric.response_time_ms
            })

        df = pd.DataFrame(data)

        if output_file is None:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            output_file = f"/var/log/blockchain/performance_data_{node_name or 'all'}_{timestamp}.csv"

        df.to_csv(output_file, index=False)
        self.logger.info(f"Performance data exported to: {output_file}")
        return output_file

def main():
    """Example usage"""
    logging.basicConfig(level=logging.INFO)

    analytics = PerformanceAnalytics()

    # Generate performance report
    report = analytics.generate_performance_report(hours=24)

    # Save report
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    report_file = f"/var/log/blockchain/performance_report_{timestamp}.json"

    with open(report_file, 'w') as f:
        json.dump(report, f, indent=2, default=str)

    print(f"Performance report generated: {report_file}")
    print(f"Summary: {report['summary']}")

if __name__ == "__main__":
    main()