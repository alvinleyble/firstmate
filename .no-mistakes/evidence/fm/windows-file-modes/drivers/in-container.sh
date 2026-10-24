set -u
mkdir -p /work/base /work/target
cp -r /src/scratch/base/bin /work/base/bin
cp -r /src/target/bin /work/target/bin
echo "container: $(uname -sr) bash $BASH_VERSION OSTYPE=$OSTYPE"
for force in native msys cygwin; do
  for root in base target; do
    bash /src/scratch/tools/lin-matrix.sh /work/$root "$force" > /work/$root-$force.txt 2>&1
  done
  if cmp -s /work/base-$force.txt /work/target-$force.txt; then same="IDENTICAL"; else same="DIFFERENT"; fi
  echo; echo "### OSTYPE=$force on a bits-keeping filesystem: base vs target output $same"
  echo "--- target ---"; cat /work/target-$force.txt
  [ "$same" = IDENTICAL ] || { echo "--- diff base target ---"; diff /work/base-$force.txt /work/target-$force.txt; }
done
