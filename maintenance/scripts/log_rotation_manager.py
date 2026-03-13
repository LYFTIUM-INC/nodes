#!/usr/bin/env python3
"""
Advanced Log Rotation and Cleanup Manager for Blockchain Nodes
Handles log rotation, compression, cleanup, and analysis
"""

import os
import gzip
import shutil
import json
import logging
import sqlite3
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Any, Optional
import yaml
import re
import subprocess
import asyncio
import tarfile
from collections import defaultdict

class LogRotationManager:
    def __init__(self, config_path: str = "/data/blockchain/nodes/maintenance/configs/log_rotation_config.yaml"):
        self.config = self._load_config(config_path)
        self.logger = self._setup_logging()
        self.log_metrics_db = Path("/data/blockchain/nodes/maintenance/logs/log_metrics.db")
        self._init_database()
        
    def _load_config(self, config_path: str) -> Dict:
        """Load log rotation configuration"""
        with open(config_path, 'r') as f:
            return yaml.safe_load(f)
            
    def _setup_logging(self) -> logging.Logger:
        """Setup logging for the log manager itself"""
        logger = logging.getLogger('LogRotationManager')
        logger.setLevel(logging.INFO)
        
        handler = logging.FileHandler('/data/blockchain/nodes/maintenance/logs/log_rotation.log')
        handler.setLevel(logging.INFO)
        
        formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
        handler.setFormatter(formatter)
        
        logger.addHandler(handler)
        return logger
        
    def _init_database(self):
        """Initialize database for log metrics"""
        conn = sqlite3.connect(str(self.log_metrics_db))
        cursor = conn.cursor()
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS log_metrics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                log_source TEXT NOT NULL,
                file_path TEXT NOT NULL,
                file_size_mb REAL,
                lines_count INTEGER,
                error_count INTEGER,
                warning_count INTEGER,
                rotation_action TEXT,
                compression_ratio REAL
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS disk_usage (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                path TEXT NOT NULL,
                total_gb REAL,
                used_gb REAL,
                free_gb REAL,
                percent_used REAL
            )
        ''')
        
        conn.commit()
        conn.close()
        
    def rotate_logs(self):
        """Rotate all configured logs"""
        self.logger.info("Starting log rotation cycle")
        
        total_space_saved = 0
        rotation_summary = {
            'timestamp': datetime.now().isoformat(),
            'rotations': [],
            'errors': [],
            'total_space_saved_mb': 0
        }
        
        for log_source, config in self.config['logs'].items():
            try:
                if config.get('enabled', True):
                    result = self._rotate_log_source(log_source, config)
                    rotation_summary['rotations'].append(result)
                    total_space_saved += result.get('space_saved_mb', 0)
                    
            except Exception as e:
                error_msg = f"Failed to rotate logs for {log_source}: {str(e)}"
                self.logger.error(error_msg)
                rotation_summary['errors'].append(error_msg)
                
        rotation_summary['total_space_saved_mb'] = total_space_saved
        
        # Save rotation summary
        summary_path = Path("/data/blockchain/nodes/maintenance/logs/rotation_summary.json")
        with open(summary_path, 'w') as f:
            json.dump(rotation_summary, f, indent=2)
            
        self.logger.info(f"Log rotation complete. Space saved: {total_space_saved:.2f} MB")
        
        # Cleanup old rotation summaries
        self._cleanup_old_summaries()
        
        return rotation_summary
        
    def _rotate_log_source(self, log_source: str, config: Dict) -> Dict:
        """Rotate logs for a specific source"""
        log_path = Path(config['path'])
        max_size_mb = config.get('max_size_mb', 100)
        max_age_days = config.get('max_age_days', 7)
        keep_files = config.get('keep_files', 5)
        compress = config.get('compress', True)
        
        result = {
            'log_source': log_source,
            'timestamp': datetime.now().isoformat(),
            'actions': [],
            'space_saved_mb': 0,
            'files_processed': 0
        }
        
        if not log_path.exists():
            result['actions'].append(f"Log file {log_path} does not exist")
            return result
            
        # Analyze current log file
        file_stats = self._analyze_log_file(log_path)
        
        # Check if rotation is needed
        needs_rotation = False
        
        if file_stats['size_mb'] > max_size_mb:
            needs_rotation = True
            result['actions'].append(f"Size-based rotation: {file_stats['size_mb']:.2f} MB > {max_size_mb} MB")
            
        if file_stats['age_hours'] > (max_age_days * 24):
            needs_rotation = True
            result['actions'].append(f"Age-based rotation: {file_stats['age_hours']:.1f} hours > {max_age_days * 24} hours")
            
        if needs_rotation:
            # Perform rotation
            rotated_file = self._perform_rotation(log_path, compress)
            result['files_processed'] += 1
            result['space_saved_mb'] += file_stats['size_mb']
            
            if compress:
                compressed_size = os.path.getsize(rotated_file) / (1024 * 1024)
                compression_ratio = compressed_size / file_stats['size_mb'] if file_stats['size_mb'] > 0 else 0
                result['actions'].append(f"Compressed to {rotated_file} (ratio: {compression_ratio:.2f})")
                
                # Update space saved calculation
                result['space_saved_mb'] = file_stats['size_mb'] - compressed_size
            else:
                result['actions'].append(f"Rotated to {rotated_file}")
                
        # Cleanup old rotated files
        cleanup_result = self._cleanup_old_rotated_files(log_path.parent, log_path.stem, keep_files)
        result['actions'].extend(cleanup_result['actions'])
        result['space_saved_mb'] += cleanup_result['space_saved_mb']
        result['files_processed'] += cleanup_result['files_removed']
        
        # Store metrics
        self._store_log_metrics(log_source, str(log_path), file_stats, 
                              'rotated' if needs_rotation else 'checked')
        
        return result
        
    def _analyze_log_file(self, log_path: Path) -> Dict:
        """Analyze log file for size, age, and content"""
        try:
            stat = log_path.stat()
            size_mb = stat.st_size / (1024 * 1024)
            age_hours = (datetime.now().timestamp() - stat.st_mtime) / 3600
            
            # Analyze content
            error_count = 0
            warning_count = 0
            lines_count = 0
            
            # Use efficient line counting for large files
            if size_mb > 50:  # For large files, sample analysis
                lines_count = self._count_lines_efficient(log_path)
                error_count, warning_count = self._sample_log_analysis(log_path)
            else:
                with open(log_path, 'r', encoding='utf-8', errors='ignore') as f:
                    for line in f:
                        lines_count += 1
                        line_lower = line.lower()
                        if 'error' in line_lower or 'fatal' in line_lower:
                            error_count += 1
                        elif 'warning' in line_lower or 'warn' in line_lower:
                            warning_count += 1
                            
            return {
                'size_mb': size_mb,
                'age_hours': age_hours,
                'lines_count': lines_count,
                'error_count': error_count,
                'warning_count': warning_count,
                'last_modified': datetime.fromtimestamp(stat.st_mtime).isoformat()
            }
            
        except Exception as e:
            self.logger.error(f"Failed to analyze log file {log_path}: {str(e)}")
            return {
                'size_mb': 0,
                'age_hours': 0,
                'lines_count': 0,
                'error_count': 0,
                'warning_count': 0,
                'last_modified': datetime.now().isoformat()
            }
            
    def _count_lines_efficient(self, file_path: Path) -> int:
        """Efficiently count lines in large files"""
        try:
            result = subprocess.run(['wc', '-l', str(file_path)], 
                                  capture_output=True, text=True, timeout=30)
            if result.returncode == 0:
                return int(result.stdout.split()[0])
        except:
            pass
            
        # Fallback method
        lines = 0
        with open(file_path, 'rb') as f:
            buffer_size = 1024 * 1024
            while chunk := f.read(buffer_size):
                lines += chunk.count(b'\n')
        return lines
        
    def _sample_log_analysis(self, log_path: Path, sample_lines: int = 1000) -> tuple:
        """Sample-based analysis for large log files"""
        error_count = 0
        warning_count = 0
        
        try:
            file_size = log_path.stat().st_size
            
            # Sample from beginning, middle, and end
            sample_positions = [0, file_size // 2, max(0, file_size - 100000)]
            
            with open(log_path, 'r', encoding='utf-8', errors='ignore') as f:
                for pos in sample_positions:
                    f.seek(pos)
                    if pos > 0:
                        f.readline()  # Skip partial line
                        
                    for _ in range(sample_lines // 3):
                        line = f.readline()
                        if not line:
                            break
                            
                        line_lower = line.lower()
                        if 'error' in line_lower or 'fatal' in line_lower:
                            error_count += 1
                        elif 'warning' in line_lower or 'warn' in line_lower:
                            warning_count += 1
                            
        except Exception as e:
            self.logger.error(f"Sample analysis failed for {log_path}: {str(e)}")
            
        return error_count, warning_count
        
    def _perform_rotation(self, log_path: Path, compress: bool = True) -> str:
        """Perform the actual log rotation"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        if compress:
            rotated_file = f"{log_path}.{timestamp}.gz"
            
            with open(log_path, 'rb') as f_in:
                with gzip.open(rotated_file, 'wb') as f_out:
                    shutil.copyfileobj(f_in, f_out)
        else:
            rotated_file = f"{log_path}.{timestamp}"
            shutil.copy2(log_path, rotated_file)
            
        # Truncate original log file
        with open(log_path, 'w') as f:
            pass
            
        # Restart log service if configured
        log_config = None
        for source, config in self.config['logs'].items():
            if Path(config['path']) == log_path:
                log_config = config
                break
                
        if log_config and log_config.get('restart_service'):
            self._restart_service(log_config['restart_service'])
            
        return rotated_file
        
    def _cleanup_old_rotated_files(self, log_dir: Path, log_name: str, keep_files: int) -> Dict:
        """Clean up old rotated files"""
        result = {
            'actions': [],
            'space_saved_mb': 0,
            'files_removed': 0
        }
        
        # Find all rotated files
        rotated_files = []
        for file_path in log_dir.glob(f"{log_name}.*"):
            if file_path.name != log_name:  # Skip the current log file
                rotated_files.append(file_path)
                
        # Sort by modification time (newest first)
        rotated_files.sort(key=lambda x: x.stat().st_mtime, reverse=True)
        
        # Remove files beyond keep_files limit
        files_to_remove = rotated_files[keep_files:]
        
        for file_path in files_to_remove:
            try:
                size_mb = file_path.stat().st_size / (1024 * 1024)
                file_path.unlink()
                
                result['files_removed'] += 1
                result['space_saved_mb'] += size_mb
                result['actions'].append(f"Removed old log file: {file_path.name} ({size_mb:.2f} MB)")
                
            except Exception as e:
                self.logger.error(f"Failed to remove {file_path}: {str(e)}")
                
        return result
        
    def _restart_service(self, service_name: str):
        """Restart a systemd service"""
        try:
            subprocess.run(['systemctl', 'reload', service_name], 
                         check=True, timeout=30)
            self.logger.info(f"Reloaded service: {service_name}")
        except subprocess.CalledProcessError:
            try:
                subprocess.run(['systemctl', 'restart', service_name], 
                             check=True, timeout=60)
                self.logger.info(f"Restarted service: {service_name}")
            except Exception as e:
                self.logger.error(f"Failed to restart service {service_name}: {str(e)}")
        except Exception as e:
            self.logger.error(f"Failed to reload/restart service {service_name}: {str(e)}")
            
    def _store_log_metrics(self, log_source: str, file_path: str, stats: Dict, action: str):
        """Store log metrics in database"""
        conn = sqlite3.connect(str(self.log_metrics_db))
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO log_metrics 
            (log_source, file_path, file_size_mb, lines_count, error_count, warning_count, rotation_action)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', (log_source, file_path, stats['size_mb'], stats['lines_count'],
              stats['error_count'], stats['warning_count'], action))
              
        conn.commit()
        conn.close()
        
    def _cleanup_old_summaries(self):
        """Clean up old rotation summary files"""
        summaries_dir = Path("/data/blockchain/nodes/maintenance/logs")
        cutoff_date = datetime.now() - timedelta(days=30)
        
        for summary_file in summaries_dir.glob("rotation_summary_*.json"):
            try:
                if summary_file.stat().st_mtime < cutoff_date.timestamp():
                    summary_file.unlink()
                    self.logger.info(f"Removed old summary: {summary_file.name}")
            except Exception as e:
                self.logger.error(f"Failed to remove old summary {summary_file}: {str(e)}")
                
    def analyze_log_patterns(self, hours: int = 24) -> Dict:
        """Analyze log patterns and generate insights"""
        conn = sqlite3.connect(str(self.log_metrics_db))
        cursor = conn.cursor()
        
        start_time = (datetime.now() - timedelta(hours=hours)).isoformat()
        
        # Get log statistics
        cursor.execute('''
            SELECT log_source, 
                   AVG(file_size_mb) as avg_size,
                   SUM(error_count) as total_errors,
                   SUM(warning_count) as total_warnings,
                   COUNT(*) as measurements
            FROM log_metrics
            WHERE timestamp > ?
            GROUP BY log_source
        ''', (start_time,))
        
        log_stats = {}
        for row in cursor.fetchall():
            log_stats[row[0]] = {
                'avg_size_mb': round(row[1], 2),
                'total_errors': row[2],
                'total_warnings': row[3],
                'measurements': row[4]
            }
            
        # Identify problematic sources
        problematic_sources = []
        for source, stats in log_stats.items():
            error_rate = stats['total_errors'] / stats['measurements'] if stats['measurements'] > 0 else 0
            if error_rate > 10:  # More than 10 errors per measurement
                problematic_sources.append({
                    'source': source,
                    'error_rate': error_rate,
                    'total_errors': stats['total_errors']
                })
                
        # Growth analysis
        cursor.execute('''
            SELECT log_source, timestamp, file_size_mb
            FROM log_metrics
            WHERE timestamp > ?
            ORDER BY log_source, timestamp
        ''', (start_time,))
        
        growth_analysis = defaultdict(list)
        for row in cursor.fetchall():
            growth_analysis[row[0]].append((row[1], row[2]))
            
        growth_rates = {}
        for source, measurements in growth_analysis.items():
            if len(measurements) > 1:
                first_size = measurements[0][1]
                last_size = measurements[-1][1]
                time_diff_hours = (datetime.fromisoformat(measurements[-1][0]) - 
                                 datetime.fromisoformat(measurements[0][0])).total_seconds() / 3600
                
                if time_diff_hours > 0:
                    growth_rate_mb_per_hour = (last_size - first_size) / time_diff_hours
                    growth_rates[source] = round(growth_rate_mb_per_hour, 2)
                    
        conn.close()
        
        return {
            'analysis_period_hours': hours,
            'generated_at': datetime.now().isoformat(),
            'log_statistics': log_stats,
            'problematic_sources': problematic_sources,
            'growth_rates_mb_per_hour': growth_rates,
            'recommendations': self._generate_recommendations(log_stats, growth_rates, problematic_sources)
        }
        
    def _generate_recommendations(self, log_stats: Dict, growth_rates: Dict, 
                                problematic_sources: List) -> List[str]:
        """Generate maintenance recommendations"""
        recommendations = []
        
        # Size-based recommendations
        for source, stats in log_stats.items():
            if stats['avg_size_mb'] > 500:
                recommendations.append(
                    f"Consider reducing log level or increasing rotation frequency for {source} "
                    f"(avg size: {stats['avg_size_mb']} MB)"
                )
                
        # Growth-based recommendations
        for source, rate in growth_rates.items():
            if rate > 50:  # Growing more than 50 MB/hour
                recommendations.append(
                    f"High log growth rate for {source}: {rate} MB/hour - consider log optimization"
                )
                
        # Error-based recommendations
        for source_info in problematic_sources:
            recommendations.append(
                f"High error rate in {source_info['source']}: {source_info['error_rate']:.1f} errors/check - "
                "investigate underlying issues"
            )
            
        if not recommendations:
            recommendations.append("All log sources are operating within normal parameters")
            
        return recommendations
        
    def emergency_cleanup(self, target_free_gb: float = 10) -> Dict:
        """Emergency disk cleanup when space is critically low"""
        self.logger.warning(f"Starting emergency cleanup to free {target_free_gb} GB")
        
        cleanup_result = {
            'timestamp': datetime.now().isoformat(),
            'target_free_gb': target_free_gb,
            'actions': [],
            'space_freed_gb': 0
        }
        
        # Get current disk usage
        disk_usage = shutil.disk_usage('/data/blockchain/nodes')
        free_gb = disk_usage.free / (1024**3)
        
        if free_gb >= target_free_gb:
            cleanup_result['actions'].append(f"Sufficient free space available: {free_gb:.2f} GB")
            return cleanup_result
            
        # Emergency cleanup strategies (in order of preference)
        strategies = [
            self._cleanup_old_compressed_logs,
            self._cleanup_old_databases,
            self._cleanup_temp_files,
            self._compress_recent_logs,
            self._truncate_large_logs
        ]
        
        for strategy in strategies:
            try:
                result = strategy()
                cleanup_result['actions'].extend(result['actions'])
                cleanup_result['space_freed_gb'] += result['space_freed_gb']
                
                # Check if we've freed enough space
                disk_usage = shutil.disk_usage('/data/blockchain/nodes')
                current_free_gb = disk_usage.free / (1024**3)
                
                if current_free_gb >= target_free_gb:
                    cleanup_result['actions'].append(f"Target achieved: {current_free_gb:.2f} GB free")
                    break
                    
            except Exception as e:
                error_msg = f"Emergency cleanup strategy failed: {str(e)}"
                self.logger.error(error_msg)
                cleanup_result['actions'].append(error_msg)
                
        return cleanup_result
        
    def _cleanup_old_compressed_logs(self) -> Dict:
        """Remove old compressed log files"""
        result = {'actions': [], 'space_freed_gb': 0}
        
        # Look for compressed logs older than 14 days
        cutoff_date = datetime.now() - timedelta(days=14)
        log_dirs = [
            Path("/data/blockchain/nodes/logs"),
            Path("/data/blockchain/nodes/maintenance/logs")
        ]
        
        for log_dir in log_dirs:
            if log_dir.exists():
                for compressed_log in log_dir.glob("*.gz"):
                    try:
                        if compressed_log.stat().st_mtime < cutoff_date.timestamp():
                            size_gb = compressed_log.stat().st_size / (1024**3)
                            compressed_log.unlink()
                            result['space_freed_gb'] += size_gb
                            result['actions'].append(f"Removed old compressed log: {compressed_log.name}")
                    except Exception as e:
                        result['actions'].append(f"Failed to remove {compressed_log}: {str(e)}")
                        
        return result
        
    def _cleanup_old_databases(self) -> Dict:
        """Clean up old database records"""
        result = {'actions': [], 'space_freed_gb': 0}
        
        # Clean up old metrics (keep only 7 days)
        cutoff_date = (datetime.now() - timedelta(days=7)).isoformat()
        
        conn = sqlite3.connect(str(self.log_metrics_db))
        cursor = conn.cursor()
        
        # Count records to be deleted
        cursor.execute('SELECT COUNT(*) FROM log_metrics WHERE timestamp < ?', (cutoff_date,))
        old_records = cursor.fetchone()[0]
        
        if old_records > 0:
            cursor.execute('DELETE FROM log_metrics WHERE timestamp < ?', (cutoff_date,))
            cursor.execute('VACUUM')
            conn.commit()
            
            result['actions'].append(f"Removed {old_records} old database records")
            result['space_freed_gb'] += old_records * 0.001  # Estimate
            
        conn.close()
        return result
        
    def _cleanup_temp_files(self) -> Dict:
        """Clean up temporary files"""
        result = {'actions': [], 'space_freed_gb': 0}
        
        temp_patterns = [
            "/tmp/blockchain-*",
            "/data/blockchain/nodes/*/tmp/*",
            "/data/blockchain/nodes/*/*.tmp"
        ]
        
        for pattern in temp_patterns:
            for temp_file in Path('/').glob(pattern.lstrip('/')):
                try:
                    if temp_file.is_file():
                        size_gb = temp_file.stat().st_size / (1024**3)
                        temp_file.unlink()
                        result['space_freed_gb'] += size_gb
                        result['actions'].append(f"Removed temp file: {temp_file}")
                except Exception as e:
                    result['actions'].append(f"Failed to remove {temp_file}: {str(e)}")
                    
        return result
        
    def _compress_recent_logs(self) -> Dict:
        """Compress recent large log files"""
        result = {'actions': [], 'space_freed_gb': 0}
        
        # Find large uncompressed logs
        for log_source, config in self.config['logs'].items():
            log_path = Path(config['path'])
            
            if log_path.exists() and log_path.stat().st_size > 100 * 1024 * 1024:  # > 100MB
                try:
                    original_size = log_path.stat().st_size
                    compressed_path = f"{log_path}.emergency.gz"
                    
                    with open(log_path, 'rb') as f_in:
                        with gzip.open(compressed_path, 'wb') as f_out:
                            shutil.copyfileobj(f_in, f_out)
                            
                    # Replace original with compressed
                    log_path.unlink()
                    Path(compressed_path).rename(log_path.with_suffix('.gz'))
                    
                    # Create new empty log file
                    log_path.touch()
                    
                    compressed_size = Path(log_path.with_suffix('.gz')).stat().st_size
                    space_saved = (original_size - compressed_size) / (1024**3)
                    
                    result['space_freed_gb'] += space_saved
                    result['actions'].append(f"Compressed {log_source} log: saved {space_saved:.2f} GB")
                    
                except Exception as e:
                    result['actions'].append(f"Failed to compress {log_source}: {str(e)}")
                    
        return result
        
    def _truncate_large_logs(self) -> Dict:
        """Last resort: truncate large log files (keep only recent entries)"""
        result = {'actions': [], 'space_freed_gb': 0}
        
        for log_source, config in self.config['logs'].items():
            log_path = Path(config['path'])
            
            if log_path.exists() and log_path.stat().st_size > 500 * 1024 * 1024:  # > 500MB
                try:
                    original_size = log_path.stat().st_size
                    
                    # Keep only last 10000 lines
                    result_proc = subprocess.run(
                        ['tail', '-n', '10000', str(log_path)],
                        capture_output=True, text=True, timeout=60
                    )
                    
                    if result_proc.returncode == 0:
                        with open(log_path, 'w') as f:
                            f.write(result_proc.stdout)
                            
                        new_size = log_path.stat().st_size
                        space_saved = (original_size - new_size) / (1024**3)
                        
                        result['space_freed_gb'] += space_saved
                        result['actions'].append(
                            f"Truncated {log_source} log to last 10000 lines: saved {space_saved:.2f} GB"
                        )
                        
                except Exception as e:
                    result['actions'].append(f"Failed to truncate {log_source}: {str(e)}")
                    
        return result

def main():
    """Main function"""
    manager = LogRotationManager()
    
    # Run log rotation
    rotation_result = manager.rotate_logs()
    print(f"Log rotation completed: {rotation_result['total_space_saved_mb']:.2f} MB saved")
    
    # Generate analysis
    analysis = manager.analyze_log_patterns(24)
    print(f"Log analysis complete: {len(analysis['recommendations'])} recommendations")

if __name__ == "__main__":
    main()