#!/usr/bin/env python3
"""
Comprehensive Backup Manager for Blockchain Nodes
Handles automated backups, verification, restoration, and disaster recovery
"""

import os
import json
import shutil
import logging
import sqlite3
import subprocess
import asyncio
import hashlib
import tarfile
import tempfile
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple
import yaml
import boto3
from botocore.exceptions import ClientError
import paramiko

class BackupManager:
    def __init__(self, config_path: str = "/data/blockchain/nodes/maintenance/configs/backup_config.yaml"):
        self.config = self._load_config(config_path)
        self.logger = self._setup_logging()
        self.backup_db = Path("/data/blockchain/nodes/maintenance/logs/backup_history.db")
        self._init_database()
        
    def _load_config(self, config_path: str) -> Dict:
        """Load backup configuration"""
        with open(config_path, 'r') as f:
            return yaml.safe_load(f)
            
    def _setup_logging(self) -> logging.Logger:
        """Setup logging"""
        logger = logging.getLogger('BackupManager')
        logger.setLevel(logging.INFO)
        
        handler = logging.FileHandler('/data/blockchain/nodes/maintenance/logs/backup.log')
        handler.setLevel(logging.INFO)
        
        formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
        handler.setFormatter(formatter)
        
        logger.addHandler(handler)
        return logger
        
    def _init_database(self):
        """Initialize backup history database"""
        conn = sqlite3.connect(str(self.backup_db))
        cursor = conn.cursor()
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS backups (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                backup_type TEXT NOT NULL,
                source TEXT NOT NULL,
                destination TEXT NOT NULL,
                size_mb REAL,
                duration_seconds REAL,
                status TEXT NOT NULL,
                checksum TEXT,
                error_message TEXT,
                retention_date DATETIME
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS backup_verification (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                backup_id INTEGER,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                verification_type TEXT NOT NULL,
                status TEXT NOT NULL,
                details TEXT,
                FOREIGN KEY (backup_id) REFERENCES backups (id)
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS restore_operations (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                backup_id INTEGER,
                restore_path TEXT NOT NULL,
                status TEXT NOT NULL,
                duration_seconds REAL,
                error_message TEXT,
                FOREIGN KEY (backup_id) REFERENCES backups (id)
            )
        ''')
        
        conn.commit()
        conn.close()
        
    def create_backup(self, backup_type: str, source_paths: List[str], 
                     destination: str, compress: bool = True, 
                     verify: bool = True) -> Dict[str, Any]:
        """Create a backup of specified paths"""
        start_time = datetime.now()
        
        backup_result = {
            'backup_type': backup_type,
            'timestamp': start_time.isoformat(),
            'source_paths': source_paths,
            'destination': destination,
            'status': 'started',
            'size_mb': 0,
            'duration_seconds': 0,
            'checksum': None,
            'error_message': None
        }
        
        try:
            self.logger.info(f"Starting {backup_type} backup to {destination}")
            
            # Ensure destination directory exists
            Path(destination).parent.mkdir(parents=True, exist_ok=True)
            
            # Create backup
            if compress:
                backup_result['destination'] = self._create_compressed_backup(
                    source_paths, destination, backup_type
                )
            else:
                backup_result['destination'] = self._create_uncompressed_backup(
                    source_paths, destination, backup_type
                )
                
            # Calculate backup size and checksum
            backup_path = Path(backup_result['destination'])
            if backup_path.exists():
                backup_result['size_mb'] = backup_path.stat().st_size / (1024 * 1024)
                backup_result['checksum'] = self._calculate_checksum(backup_path)
                backup_result['status'] = 'completed'
                
                self.logger.info(f"Backup completed: {backup_result['size_mb']:.2f} MB")
                
                # Verify backup if requested
                if verify:
                    verification_result = self._verify_backup(backup_result['destination'])
                    backup_result['verification'] = verification_result
                    
                # Upload to remote storage if configured
                if self.config.get('remote_storage', {}).get('enabled'):
                    upload_result = self._upload_to_remote(backup_result['destination'])
                    backup_result['remote_upload'] = upload_result
                    
            else:
                backup_result['status'] = 'failed'
                backup_result['error_message'] = 'Backup file not created'
                
        except Exception as e:
            backup_result['status'] = 'failed'
            backup_result['error_message'] = str(e)
            self.logger.error(f"Backup failed: {str(e)}")
            
        # Calculate duration
        backup_result['duration_seconds'] = (datetime.now() - start_time).total_seconds()
        
        # Store backup record
        self._store_backup_record(backup_result)
        
        return backup_result
        
    def _create_compressed_backup(self, source_paths: List[str], 
                                destination: str, backup_type: str) -> str:
        """Create compressed tar.gz backup"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_filename = f"{backup_type}_{timestamp}.tar.gz"
        backup_path = Path(destination) / backup_filename
        
        with tarfile.open(backup_path, 'w:gz') as tar:
            for source_path in source_paths:
                source = Path(source_path)
                if source.exists():
                    if source.is_dir():
                        # Add directory recursively with relative paths
                        tar.add(source, arcname=source.name)
                    else:
                        # Add single file
                        tar.add(source, arcname=source.name)
                else:
                    self.logger.warning(f"Source path does not exist: {source_path}")
                    
        return str(backup_path)
        
    def _create_uncompressed_backup(self, source_paths: List[str], 
                                  destination: str, backup_type: str) -> str:
        """Create uncompressed directory-based backup"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_dir = Path(destination) / f"{backup_type}_{timestamp}"
        backup_dir.mkdir(parents=True, exist_ok=True)
        
        for source_path in source_paths:
            source = Path(source_path)
            if source.exists():
                dest_path = backup_dir / source.name
                if source.is_dir():
                    shutil.copytree(source, dest_path)
                else:
                    shutil.copy2(source, dest_path)
            else:
                self.logger.warning(f"Source path does not exist: {source_path}")
                
        return str(backup_dir)
        
    def _calculate_checksum(self, file_path: Path) -> str:
        """Calculate SHA256 checksum of file or directory"""
        if file_path.is_file():
            hash_sha256 = hashlib.sha256()
            with open(file_path, "rb") as f:
                for chunk in iter(lambda: f.read(4096), b""):
                    hash_sha256.update(chunk)
            return hash_sha256.hexdigest()
        else:
            # For directories, calculate hash of all files
            hash_sha256 = hashlib.sha256()
            for file_path in sorted(file_path.rglob('*')):
                if file_path.is_file():
                    with open(file_path, "rb") as f:
                        for chunk in iter(lambda: f.read(4096), b""):
                            hash_sha256.update(chunk)
            return hash_sha256.hexdigest()
            
    def _verify_backup(self, backup_path: str) -> Dict[str, Any]:
        """Verify backup integrity"""
        verification_result = {
            'timestamp': datetime.now().isoformat(),
            'backup_path': backup_path,
            'status': 'started',
            'checks': {},
            'error_message': None
        }
        
        try:
            backup_file = Path(backup_path)
            
            # Check file exists and is readable
            if not backup_file.exists():
                verification_result['status'] = 'failed'
                verification_result['error_message'] = 'Backup file does not exist'
                return verification_result
                
            verification_result['checks']['file_exists'] = True
            
            # Check file size is reasonable
            size_mb = backup_file.stat().st_size / (1024 * 1024)
            verification_result['checks']['file_size_mb'] = size_mb
            
            if size_mb < 0.1:  # Less than 100KB seems suspicious
                verification_result['checks']['size_reasonable'] = False
                verification_result['error_message'] = f'Backup size too small: {size_mb:.2f} MB'
            else:
                verification_result['checks']['size_reasonable'] = True
                
            # If it's a tar.gz file, verify it can be opened
            if backup_path.endswith('.tar.gz'):
                try:
                    with tarfile.open(backup_path, 'r:gz') as tar:
                        # Try to list contents
                        members = tar.getnames()
                        verification_result['checks']['archive_valid'] = True
                        verification_result['checks']['archive_members_count'] = len(members)
                except Exception as e:
                    verification_result['checks']['archive_valid'] = False
                    verification_result['error_message'] = f'Archive verification failed: {str(e)}'
                    
            # Calculate and store checksum
            checksum = self._calculate_checksum(backup_file)
            verification_result['checksum'] = checksum
            
            # Determine overall status
            if all(verification_result['checks'].values()):
                verification_result['status'] = 'passed'
            else:
                verification_result['status'] = 'failed'
                
        except Exception as e:
            verification_result['status'] = 'failed'
            verification_result['error_message'] = str(e)
            
        return verification_result
        
    def _upload_to_remote(self, backup_path: str) -> Dict[str, Any]:
        """Upload backup to remote storage"""
        remote_config = self.config['remote_storage']
        upload_result = {
            'timestamp': datetime.now().isoformat(),
            'backup_path': backup_path,
            'storage_type': remote_config['type'],
            'status': 'started',
            'remote_path': None,
            'error_message': None
        }
        
        try:
            if remote_config['type'] == 's3':
                upload_result = self._upload_to_s3(backup_path, remote_config, upload_result)
            elif remote_config['type'] == 'sftp':
                upload_result = self._upload_to_sftp(backup_path, remote_config, upload_result)
            else:
                upload_result['status'] = 'failed'
                upload_result['error_message'] = f"Unsupported storage type: {remote_config['type']}"
                
        except Exception as e:
            upload_result['status'] = 'failed'
            upload_result['error_message'] = str(e)
            
        return upload_result
        
    def _upload_to_s3(self, backup_path: str, config: Dict, upload_result: Dict) -> Dict:
        """Upload backup to AWS S3"""
        s3_client = boto3.client(
            's3',
            aws_access_key_id=config['aws_access_key_id'],
            aws_secret_access_key=config['aws_secret_access_key'],
            region_name=config.get('region', 'us-east-1')
        )
        
        backup_file = Path(backup_path)
        s3_key = f"{config.get('prefix', 'backups')}/{backup_file.name}"
        
        try:
            s3_client.upload_file(
                str(backup_file),
                config['bucket'],
                s3_key,
                ExtraArgs={'StorageClass': config.get('storage_class', 'STANDARD')}
            )
            
            upload_result['status'] = 'completed'
            upload_result['remote_path'] = f"s3://{config['bucket']}/{s3_key}"
            
        except ClientError as e:
            upload_result['status'] = 'failed'
            upload_result['error_message'] = str(e)
            
        return upload_result
        
    def _upload_to_sftp(self, backup_path: str, config: Dict, upload_result: Dict) -> Dict:
        """Upload backup via SFTP"""
        transport = paramiko.Transport((config['host'], config.get('port', 22)))
        
        try:
            if config.get('key_file'):
                key = paramiko.RSAKey.from_private_key_file(config['key_file'])
                transport.connect(username=config['username'], pkey=key)
            else:
                transport.connect(username=config['username'], password=config['password'])
                
            sftp = paramiko.SFTPClient.from_transport(transport)
            
            backup_file = Path(backup_path)
            remote_path = f"{config.get('remote_path', '/backups')}/{backup_file.name}"
            
            sftp.put(str(backup_file), remote_path)
            
            upload_result['status'] = 'completed'
            upload_result['remote_path'] = f"sftp://{config['host']}{remote_path}"
            
        except Exception as e:
            upload_result['status'] = 'failed'
            upload_result['error_message'] = str(e)
        finally:
            transport.close()
            
        return upload_result
        
    def _store_backup_record(self, backup_result: Dict):
        """Store backup record in database"""
        conn = sqlite3.connect(str(self.backup_db))
        cursor = conn.cursor()
        
        # Calculate retention date
        retention_days = self.config.get('retention', {}).get('default_days', 30)
        retention_date = (datetime.now() + timedelta(days=retention_days)).isoformat()
        
        cursor.execute('''
            INSERT INTO backups 
            (backup_type, source, destination, size_mb, duration_seconds, 
             status, checksum, error_message, retention_date)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            backup_result['backup_type'],
            json.dumps(backup_result['source_paths']),
            backup_result['destination'],
            backup_result['size_mb'],
            backup_result['duration_seconds'],
            backup_result['status'],
            backup_result['checksum'],
            backup_result['error_message'],
            retention_date
        ))
        
        backup_id = cursor.lastrowid
        
        # Store verification record if available
        if 'verification' in backup_result:
            verification = backup_result['verification']
            cursor.execute('''
                INSERT INTO backup_verification 
                (backup_id, verification_type, status, details)
                VALUES (?, ?, ?, ?)
            ''', (
                backup_id,
                'integrity_check',
                verification['status'],
                json.dumps(verification)
            ))
            
        conn.commit()
        conn.close()
        
    def backup_node_data(self, chain: str) -> Dict[str, Any]:
        """Backup specific node data"""
        if chain not in self.config['node_backups']:
            raise ValueError(f"No backup configuration for chain: {chain}")
            
        node_config = self.config['node_backups'][chain]
        
        # Determine backup paths
        backup_paths = []
        
        # Configuration files
        if node_config.get('config_paths'):
            backup_paths.extend(node_config['config_paths'])
            
        # Data directories (selective backup to avoid huge chaindata)
        if node_config.get('data_paths'):
            for data_path in node_config['data_paths']:
                path = Path(data_path)
                if path.exists():
                    # For large data directories, backup selectively
                    if path.stat().st_size > 10 * 1024 * 1024 * 1024:  # > 10GB
                        # Backup only essential files, not full chaindata
                        backup_paths.extend(self._selective_data_backup(path, chain))
                    else:
                        backup_paths.append(str(path))
                        
        # Logs (recent only)
        if node_config.get('log_paths'):
            for log_path in node_config['log_paths']:
                backup_paths.append(log_path)
                
        # Create backup
        destination = Path(self.config['backup_destinations']['local']) / chain
        destination.mkdir(parents=True, exist_ok=True)
        
        return self.create_backup(
            backup_type=f"node_data_{chain}",
            source_paths=backup_paths,
            destination=str(destination),
            compress=True,
            verify=True
        )
        
    def _selective_data_backup(self, data_path: Path, chain: str) -> List[str]:
        """Perform selective backup of large data directories"""
        backup_paths = []
        
        # Essential files/directories to always backup
        essential_patterns = [
            'config*',
            'genesis*',
            'key*',
            'jwt*',
            'static-nodes.json',
            'trusted-nodes.json',
            'nodekey',
            'enode',
            'networkid'
        ]
        
        for pattern in essential_patterns:
            for file_path in data_path.glob(pattern):
                if file_path.is_file() and file_path.stat().st_size < 100 * 1024 * 1024:  # < 100MB
                    backup_paths.append(str(file_path))
                    
        # Chain-specific important directories
        important_dirs = {
            'ethereum': ['keystore', 'bls', 'static'],
            'polygon': ['keystore', 'config', 'data/bor/keystore'],
            'arbitrum': ['classic-msg', 'arbitrumdata/classic-msg'],
            'solana': ['config', 'identity.json', 'vote-account.json']
        }
        
        if chain in important_dirs:
            for dir_name in important_dirs[chain]:
                dir_path = data_path / dir_name
                if dir_path.exists() and dir_path.is_dir():
                    # Only backup if directory is reasonably sized
                    dir_size = sum(f.stat().st_size for f in dir_path.rglob('*') if f.is_file())
                    if dir_size < 500 * 1024 * 1024:  # < 500MB
                        backup_paths.append(str(dir_path))
                        
        return backup_paths
        
    def restore_backup(self, backup_id: int, restore_path: str, 
                      verify: bool = True) -> Dict[str, Any]:
        """Restore from backup"""
        start_time = datetime.now()
        
        restore_result = {
            'backup_id': backup_id,
            'restore_path': restore_path,
            'timestamp': start_time.isoformat(),
            'status': 'started',
            'duration_seconds': 0,
            'error_message': None
        }
        
        try:
            # Get backup information
            conn = sqlite3.connect(str(self.backup_db))
            cursor = conn.cursor()
            
            cursor.execute('SELECT * FROM backups WHERE id = ?', (backup_id,))
            backup_record = cursor.fetchone()
            
            if not backup_record:
                raise ValueError(f"Backup with ID {backup_id} not found")
                
            backup_path = backup_record[3]  # destination column
            
            if not Path(backup_path).exists():
                raise FileNotFoundError(f"Backup file not found: {backup_path}")
                
            self.logger.info(f"Starting restore from {backup_path} to {restore_path}")
            
            # Ensure restore path exists
            Path(restore_path).mkdir(parents=True, exist_ok=True)
            
            # Verify backup before restore if requested
            if verify:
                verification = self._verify_backup(backup_path)
                if verification['status'] != 'passed':
                    raise Exception(f"Backup verification failed: {verification.get('error_message')}")
                    
            # Perform restore
            if backup_path.endswith('.tar.gz'):
                self._restore_compressed_backup(backup_path, restore_path)
            else:
                self._restore_uncompressed_backup(backup_path, restore_path)
                
            restore_result['status'] = 'completed'
            self.logger.info(f"Restore completed to {restore_path}")
            
        except Exception as e:
            restore_result['status'] = 'failed'
            restore_result['error_message'] = str(e)
            self.logger.error(f"Restore failed: {str(e)}")
            
        # Calculate duration
        restore_result['duration_seconds'] = (datetime.now() - start_time).total_seconds()
        
        # Store restore record
        self._store_restore_record(restore_result)
        
        return restore_result
        
    def _restore_compressed_backup(self, backup_path: str, restore_path: str):
        """Restore from compressed backup"""
        with tarfile.open(backup_path, 'r:gz') as tar:
            tar.extractall(path=restore_path)
            
    def _restore_uncompressed_backup(self, backup_path: str, restore_path: str):
        """Restore from uncompressed backup"""
        backup_dir = Path(backup_path)
        restore_dir = Path(restore_path)
        
        for item in backup_dir.rglob('*'):
            if item.is_file():
                relative_path = item.relative_to(backup_dir)
                dest_path = restore_dir / relative_path
                dest_path.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(item, dest_path)
                
    def _store_restore_record(self, restore_result: Dict):
        """Store restore operation record"""
        conn = sqlite3.connect(str(self.backup_db))
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO restore_operations 
            (backup_id, restore_path, status, duration_seconds, error_message)
            VALUES (?, ?, ?, ?, ?)
        ''', (
            restore_result['backup_id'],
            restore_result['restore_path'],
            restore_result['status'],
            restore_result['duration_seconds'],
            restore_result['error_message']
        ))
        
        conn.commit()
        conn.close()
        
    def cleanup_old_backups(self) -> Dict[str, Any]:
        """Clean up expired backups"""
        cleanup_result = {
            'timestamp': datetime.now().isoformat(),
            'backups_removed': 0,
            'space_freed_gb': 0,
            'errors': []
        }
        
        conn = sqlite3.connect(str(self.backup_db))
        cursor = conn.cursor()
        
        # Find expired backups
        current_time = datetime.now().isoformat()
        cursor.execute('''
            SELECT id, destination, size_mb FROM backups 
            WHERE retention_date < ? AND status = 'completed'
        ''', (current_time,))
        
        expired_backups = cursor.fetchall()
        
        for backup_id, destination, size_mb in expired_backups:
            try:
                backup_path = Path(destination)
                if backup_path.exists():
                    if backup_path.is_file():
                        backup_path.unlink()
                    else:
                        shutil.rmtree(backup_path)
                        
                    cleanup_result['backups_removed'] += 1
                    cleanup_result['space_freed_gb'] += (size_mb / 1024) if size_mb else 0
                    
                    # Update backup record
                    cursor.execute('''
                        UPDATE backups SET status = 'expired' WHERE id = ?
                    ''', (backup_id,))
                    
            except Exception as e:
                error_msg = f"Failed to remove backup {backup_id}: {str(e)}"
                cleanup_result['errors'].append(error_msg)
                self.logger.error(error_msg)
                
        conn.commit()
        conn.close()
        
        self.logger.info(f"Cleanup completed: {cleanup_result['backups_removed']} backups removed, "
                        f"{cleanup_result['space_freed_gb']:.2f} GB freed")
        
        return cleanup_result
        
    def generate_backup_report(self, days: int = 7) -> Dict[str, Any]:
        """Generate backup status report"""
        conn = sqlite3.connect(str(self.backup_db))
        cursor = conn.cursor()
        
        start_date = (datetime.now() - timedelta(days=days)).isoformat()
        
        # Backup statistics
        cursor.execute('''
            SELECT backup_type, status, COUNT(*) as count, AVG(size_mb) as avg_size
            FROM backups WHERE timestamp > ?
            GROUP BY backup_type, status
        ''', (start_date,))
        
        backup_stats = {}
        for row in cursor.fetchall():
            backup_type, status, count, avg_size = row
            if backup_type not in backup_stats:
                backup_stats[backup_type] = {}
            backup_stats[backup_type][status] = {
                'count': count,
                'avg_size_mb': round(avg_size or 0, 2)
            }
            
        # Recent failures
        cursor.execute('''
            SELECT backup_type, timestamp, error_message
            FROM backups WHERE timestamp > ? AND status = 'failed'
            ORDER BY timestamp DESC LIMIT 10
        ''', (start_date,))
        
        recent_failures = [
            {
                'backup_type': row[0],
                'timestamp': row[1],
                'error_message': row[2]
            }
            for row in cursor.fetchall()
        ]
        
        # Storage usage
        cursor.execute('''
            SELECT SUM(size_mb) as total_size FROM backups 
            WHERE status = 'completed'
        ''', )
        
        total_size_mb = cursor.fetchone()[0] or 0
        
        conn.close()
        
        report = {
            'report_period_days': days,
            'generated_at': datetime.now().isoformat(),
            'backup_statistics': backup_stats,
            'recent_failures': recent_failures,
            'total_storage_usage': {
                'size_mb': round(total_size_mb, 2),
                'size_gb': round(total_size_mb / 1024, 2)
            },
            'health_summary': self._assess_backup_health(backup_stats)
        }
        
        return report
        
    def _assess_backup_health(self, backup_stats: Dict) -> Dict[str, Any]:
        """Assess overall backup system health"""
        total_backups = 0
        successful_backups = 0
        
        for backup_type, stats in backup_stats.items():
            for status, data in stats.items():
                total_backups += data['count']
                if status == 'completed':
                    successful_backups += data['count']
                    
        success_rate = (successful_backups / total_backups * 100) if total_backups > 0 else 0
        
        health_status = 'healthy'
        if success_rate < 80:
            health_status = 'critical'
        elif success_rate < 95:
            health_status = 'warning'
            
        return {
            'status': health_status,
            'success_rate': round(success_rate, 1),
            'total_backups': total_backups,
            'successful_backups': successful_backups,
            'recommendations': self._generate_backup_recommendations(success_rate, backup_stats)
        }
        
    def _generate_backup_recommendations(self, success_rate: float, 
                                       backup_stats: Dict) -> List[str]:
        """Generate backup improvement recommendations"""
        recommendations = []
        
        if success_rate < 95:
            recommendations.append(f"Success rate is {success_rate:.1f}% - investigate backup failures")
            
        # Check for missing backups
        expected_backup_types = set(self.config['node_backups'].keys())
        actual_backup_types = set(backup_stats.keys())
        
        missing_backups = expected_backup_types - actual_backup_types
        if missing_backups:
            recommendations.append(f"Missing backups for: {', '.join(missing_backups)}")
            
        # Check backup frequency
        for backup_type, stats in backup_stats.items():
            completed_count = stats.get('completed', {}).get('count', 0)
            if completed_count < 7:  # Less than daily backups in a week
                recommendations.append(f"Infrequent backups for {backup_type}: only {completed_count} in 7 days")
                
        if not recommendations:
            recommendations.append("Backup system operating normally")
            
        return recommendations

def main():
    """Main function for testing"""
    manager = BackupManager()
    
    # Run cleanup
    cleanup_result = manager.cleanup_old_backups()
    print(f"Cleanup completed: {cleanup_result['backups_removed']} backups removed")
    
    # Generate report
    report = manager.generate_backup_report()
    print(f"Backup health: {report['health_summary']['status']}")

if __name__ == "__main__":
    main()