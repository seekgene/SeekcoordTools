import setuptools
import os
import re

# Read version from __init__.py without importing
def get_version():
    init_path = os.path.join(os.path.dirname(__file__), 'seekcoord', '__init__.py')
    with open(init_path, 'r', encoding='utf-8') as f:
        content = f.read()
        version_match = re.search(r'^__VERSION__\s*=\s*["\']([^"\']*)["\']', content, re.MULTILINE)
        if version_match:
            return version_match.group(1)
        raise RuntimeError("Unable to find version string.")

def get_assay_list():
    init_path = os.path.join(os.path.dirname(__file__), 'seekcoord', '__init__.py')
    with open(init_path, 'r', encoding='utf-8') as f:
        content = f.read()
        # Match ASSAY_LIST = ["rna", ...]
        assay_match = re.search(r'^ASSAY_LIST\s*=\s*\[(.*?)\]', content, re.MULTILINE | re.DOTALL)
        if assay_match:
            assay_str = assay_match.group(1)
            # Extract quoted strings
            assays = re.findall(r'["\']([^"\']+)["\']', assay_str)
            return assays
        return ["rna"]  # Default fallback

__VERSION__ = get_version()
ASSAY_LIST = get_assay_list()

# Read requirements.txt
with open('requirements.txt', encoding='utf-8') as fp:
    install_requires = fp.read().strip().split('\n')

entrys = [
    'seekcoord=seekcoord.runner.public_cli:main',
    'seekcoord_pipeline=seekcoord.pipeline:main',
    'seekcoord_batch=seekcoord.runner.cli:batch_main',
    'seekcoord_runner=seekcoord.runner.cli:main',
    'seekcoord_report=seekcoord.tools.spatial_report_generator:main',
    'seekcoord_scrna_report=seekcoord.tools.scrna_report_generator:main',
]
for assay in ASSAY_LIST:
    entrys.append(f'multi_{assay}=seekcoord.{assay}.multi_{assay}:main')
entry_dict = {
    'console_scripts': entrys,
}

setuptools.setup(
    name='seekcoord',
    version=__VERSION__,
    author='SeekGene',
    author_email='info@seekgene.com',
    description='Spatial Transcriptomics Analysis Pipelines',
    packages=setuptools.find_packages(exclude=('tests', 'tests.*', 'private', 'private.*')),
    python_requires='>=3.11',
    include_package_data=True,
    entry_points=entry_dict,
    install_requires=install_requires,
    scripts=['SeekcoordTools.sh', 'SeekcoordTools_FFPE.sh', 'SeekcoordTools_SN.sh', 'SeekcoordTools_reanalysis.sh', 'SeekcoordTools_run.sh'],
    classifiers=[
        "Programming Language :: Python :: 3",
        "Operating System :: OS Independent",
    ],
)
