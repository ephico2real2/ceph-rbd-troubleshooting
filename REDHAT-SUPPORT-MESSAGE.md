# Red Hat Support Message - Loki Bucket Cleanup Issue

## Subject
Loki bucket objects not being cleaned up per retention policy - need guidance on safe manual cleanup

## Message Body

Hello Red Hat Support Team,

We are experiencing an issue with our OpenShift Logging (Loki) deployment where objects in the RGW bucket are not being automatically cleaned up according to the configured retention policy. We need guidance on how to safely clean up old objects without modifying Loki's retention policy configuration.

### Environment Details
- **OpenShift Version**: 4.18
- **OpenShift Data Foundation (ODF)**: Version [your version]
- **Loki Stack**: [your version]
- **Storage Backend**: Ceph RGW (RADOS Gateway) via ODF

### Issue Description

The Loki bucket (`lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7`) has grown significantly and contains approximately:
- **Size**: ~6.38 TiB
- **Object Count**: ~3.75 million objects
- **Bucket Name**: `lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7`

Despite having retention policies configured in Loki, the objects in the RGW bucket are not being automatically deleted. This is causing:
1. Storage capacity issues in our Ceph cluster
2. Near-full OSD warnings
3. Potential impact on cluster performance

### What We've Observed

1. **Loki Retention Policy**: We have retention policies configured in Loki, but they do not appear to be actively cleaning up objects in the RGW bucket.

2. **Bucket Stats**: When we check the bucket using `radosgw-admin bucket stats`, we see:
   ```bash
   radosgw-admin bucket stats --bucket=lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7
   ```
   The bucket shows significant usage but objects older than the retention period remain.

3. **Object Age**: Many objects in the bucket appear to be older than our configured retention period, yet they have not been automatically removed.

### Questions for Red Hat Support

1. **Root Cause**: Why might Loki not be cleaning up objects according to the retention policy? Are there known issues or configuration requirements we should check?

2. **Safe Cleanup Method**: What is the recommended method to manually clean up old objects from the Loki RGW bucket without:
   - Breaking Loki functionality
   - Causing data loss for logs within the retention period
   - Requiring changes to Loki retention policy configuration

3. **RGW Lifecycle Rules**: Can we safely use RGW lifecycle rules (`radosgw-admin lc`) to automatically expire old objects, or would this interfere with Loki's operations?

4. **Manual Deletion**: If manual deletion is required, what is the safest approach?
   - Should we delete objects based on modification time?
   - Are there specific object naming patterns or prefixes we should preserve?
   - What precautions should we take to avoid impacting active Loki operations?

5. **Verification**: How can we verify that objects are safe to delete before removing them?

6. **Prevention**: What steps should we take to ensure Loki properly cleans up objects going forward?

### What We've Tried

- Verified Loki retention policy configuration
- Checked bucket statistics and object counts
- Reviewed Ceph/RGW logs for any errors
- Confirmed the bucket is accessible and functional

### Requested Action

We would appreciate guidance on:
1. The recommended approach to safely clean up old objects
2. Any configuration changes needed to ensure automatic cleanup works correctly
3. Best practices for monitoring and maintaining Loki bucket size

### Additional Information

If needed, we can provide:
- Loki configuration details
- Bucket statistics output
- Relevant logs
- Cluster health status

Thank you for your assistance.

---

## Alternative Shorter Version

**Subject**: Loki RGW bucket not cleaning up objects per retention policy - need cleanup guidance

**Message**:

We have a Loki bucket (`lokistack-objectbucketclai-0674fc7d-c94f-4384-aa65-be74330200b7`) that has grown to ~6.38 TiB with ~3.75 million objects. Despite having retention policies configured in Loki, objects are not being automatically cleaned up from the RGW bucket.

**Questions**:
1. Why might Loki not be cleaning up objects automatically?
2. What is the safest method to manually clean up old objects without breaking Loki or changing retention policies?
3. Can we use RGW lifecycle rules, or should we delete objects manually based on age?
4. What precautions should we take to avoid impacting active Loki operations?

**Environment**: OpenShift 4.18, ODF, Loki Stack

We need guidance on safely reducing the bucket size while maintaining Loki functionality.
